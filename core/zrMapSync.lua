local _, ZR = ...

-- Shares where guild members are, for the world map pins.
local Map = {}
ZR.Map = Map

local PREFIX = "ZUGZUGMap"
local MAPUTILS = "MapUtils"
local PROTO = "1"
local SCALE = 10000
local SEND_EVERY = 5
local HEARTBEAT = 30
local MOVED = 0.0015
local EXPIRE = 75
local WALKED_IN = 3
local GLIDE = SEND_EVERY
local JUMP = 0.2
local SUMMON_WINDOW = 130

Map.members = {}
local last, lastOut = {}, {}
local inside, leftAt, summonAt, journal, played, muted

function Map.Showing()
  return ZR.DB().mapPins ~= false
end

function Map.Sharing()
  return ZR.DB().mapShare ~= false
end

function Map.MinimapShowing()
  return ZR.DB().mapMinimap ~= false
end

-- Where to draw a member on their own map: gliding from the last spot over one send interval.
function Map.Position(m, now)
  local t = m.moveAt and ((now or GetTime()) - m.moveAt) / GLIDE or 1
  if t >= 1 then return m.x, m.y, false end
  return m.fromX + (m.x - m.fromX) * t, m.fromY + (m.y - m.fromY) * t, true
end

local function Changed()
  ZR.Fire("MapChanged")
end

local function Send(msg)
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
  return ok and (result == nil or result == true or result == 0)
end

local function CanSend()
  if not Map.Sharing() or not IsInGuild() then return false end
  if C_GuildInfo.CanSpeakInGuildChat and not C_GuildInfo.CanSpeakInGuildChat() then return false end
  local _, kind = IsInInstance()
  return kind ~= "pvp" and kind ~= "arena"
end

local function OwnPosition()
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID or ZR.IsSecret(mapID) then return end
  local pos = C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return end
  local x, y = pos:GetXY()
  if ZR.IsSecret(x) or ZR.IsSecret(y) or not x or not y or (x == 0 and y == 0) then return end
  return mapID, x, y
end
Map.OwnPosition = OwnPosition

local function Learned()
  local db = ZR.DB()
  db.entrances = db.entrances or {}
  return db.entrances
end

-- The game's own dungeon entrances, indexed once by journal instance.
local function JournalEntrance(instanceID)
  local EJ = C_EncounterJournal
  if not EJ or not EJ.GetInstanceForGameMap or not EJ.GetDungeonEntrancesForMap or not C_Map.GetMapChildrenInfo then return end
  local ok, journalID = pcall(EJ.GetInstanceForGameMap, instanceID)
  if not ok or not journalID or ZR.IsSecret(journalID) then return end
  if not journal then
    journal = {}
    for _, root in ipairs({ 946, 947 }) do
      for _, zone in ipairs(C_Map.GetMapChildrenInfo(root, Enum.UIMapType.Zone, true) or {}) do
        local got, list = pcall(EJ.GetDungeonEntrancesForMap, zone.mapID)
        for _, e in ipairs(got and type(list) == "table" and list or {}) do
          local id, pos = e.journalInstanceID, e.position
          if id and pos and not journal[id] then
            local x, y = pos:GetXY()
            journal[id] = { zone.mapID, x, y }
          end
        end
      end
      if next(journal) then break end
    end
  end
  return journal[journalID]
end

local function FindEntrance(instanceID)
  local e = Learned()[instanceID] or JournalEntrance(instanceID)
  if e then return e[1], e[2], e[3] end
end

local function InstanceKind()
  local isIn, kind = IsInInstance()
  if ZR.IsSecret(isIn) or ZR.IsSecret(kind) or not isIn then return end
  if kind == "party" or kind == "raid" then return kind end
end

-- Inside, members show at the entrance: where we walked in, else a known spot for that dungeon.
local function EnterWorld(_, isLogin, isReload)
  inside = nil
  wipe(last)
  local kind = InstanceKind()
  if not kind then return end
  local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
  if ZR.IsSecret(name) or ZR.IsSecret(instanceID) or not instanceID then return end
  local now = GetTime()
  local walked = not isLogin and not isReload and lastOut.at and leftAt and leftAt - lastOut.at <= WALKED_IN
    and now - (summonAt or -SUMMON_WINDOW) > SUMMON_WINDOW
    and not (IsInLFGDungeon and IsInLFGDungeon())
  local mapID, x, y
  if walked then
    mapID, x, y = lastOut.mapID, lastOut.x, lastOut.y
    Learned()[instanceID] = { mapID, x, y }
  else
    mapID, x, y = FindEntrance(instanceID)
  end
  inside = { id = instanceID, name = name, raid = kind == "raid", mapID = mapID or 0, x = x or 0, y = y or 0 }
end

local function SampleOutside()
  if inside then return end
  local mapID, x, y = OwnPosition()
  if mapID then lastOut.mapID, lastOut.x, lastOut.y, lastOut.at = mapID, x, y, GetTime() end
end

local function Unmute()
  if not muted then return end
  for _, frame in ipairs(muted) do frame:RegisterEvent("TIME_PLAYED_MSG") end
  muted = nil
end

-- Asked once per login, with the chat frames muted so the reply doesn't print.
local function RequestPlayed()
  if not RequestTimePlayed or muted then return end
  muted = {}
  for i = 1, NUM_CHAT_WINDOWS or 10 do
    local frame = _G["ChatFrame" .. i]
    if frame and frame:IsEventRegistered("TIME_PLAYED_MSG") then
      frame:UnregisterEvent("TIME_PLAYED_MSG")
      muted[#muted + 1] = frame
    end
  end
  RequestTimePlayed()
  C_Timer.After(10, Unmute)
end

local function PlayedNow()
  return played and math.floor(played.total + GetTime() - played.at) or ""
end

-- Sends only after moving, plus a heartbeat so pins never expire while standing still.
local function Broadcast()
  if not CanSend() then return end
  local mapID, x, y
  if inside then
    mapID, x, y = inside.mapID, inside.x, inside.y
  else
    mapID, x, y = OwnPosition()
    if not mapID then return end
  end
  local onTaxi = UnitOnTaxi("player")
  local taxi = (not inside and not ZR.IsSecret(onTaxi) and onTaxi) and "1" or "0"
  local inst = inside and inside.id or 0
  local now = GetTime()
  local moved = last.mapID ~= mapID or last.taxi ~= taxi or last.inst ~= inst
    or math.abs(x - last.x) > MOVED or math.abs(y - last.y) > MOVED
  if not moved and now - last.at < HEARTBEAT then return end
  local _, class = UnitClass("player")
  -- Extra fields go last, so older versions still read the first eight as a normal position.
  local fields = { PROTO, "P", mapID, math.floor(x * SCALE + 0.5), math.floor(y * SCALE + 0.5),
    UnitLevel("player") or 0, class or "", taxi,
    inside and inside.id or "", inside and (inside.raid and "r" or "d") or "",
    inside and inside.name:gsub("|", ""):sub(1, 60) or "", PlayedNow() }
  -- A blocked send retries next tick instead of waiting for the heartbeat.
  if not Send(table.concat(fields, "|")) then return end
  last.mapID, last.x, last.y, last.taxi, last.inst, last.at = mapID, x, y, taxi, inst, now
end

local function Remove(name)
  if Map.members[name] then
    Map.members[name] = nil
    Changed()
  end
end

local function Store(name, source, mapID, x, y, level, class, taxi, instance, playedSecs)
  if not name or name == "" or name == ZR.PlayerName() then return end
  if instance then
    if mapID and mapID > 0 then
      Learned()[instance.id] = Learned()[instance.id] or { mapID, x, y }
    else
      mapID, x, y = FindEntrance(instance.id)
    end
    -- No known entrance: drop the old outdoor pin rather than leave it misleading.
    if not mapID then return Remove(name) end
  end
  if not mapID or mapID <= 0 or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return end
  local now = GetTime()
  local m = Map.members[name]
  -- Ours carries more, so a MapUtils copy of the same player never replaces a fresh one.
  if m and m.source == "zz" and source ~= "zz" and now - m.at < EXPIRE then return end
  m = m or { name = name }
  Map.members[name] = m
  -- Short moves glide; zone changes, teleports and dungeons snap.
  local fromX, fromY
  if m.mapID == mapID and m.x and not instance and not m.instance and now - m.at < EXPIRE then
    local cx, cy = Map.Position(m, now)
    local dx, dy = math.abs(cx - x), math.abs(cy - y)
    if dx < JUMP and dy < JUMP and dx + dy > 0.0001 then fromX, fromY = cx, cy end
  end
  m.fromX, m.fromY, m.moveAt = fromX, fromY, fromX and now or nil
  m.source, m.mapID, m.x, m.y, m.taxi, m.instance, m.at = source, mapID, x, y, taxi, instance, now
  if level and level > 0 then m.level = level end
  if playedSecs then m.played, m.playedAt = playedSecs, now end
  if class and RAID_CLASS_COLORS[class] then m.class = class end
  Changed()
end

function Map.Get(name)
  local m = name and Map.members[name]
  if m and GetTime() - m.at < EXPIRE then return m end
end

-- Members seen recently enough to draw.
function Map.Active()
  local out, now = {}, GetTime()
  for name, m in pairs(Map.members) do
    if now - m.at < EXPIRE then out[name] = m end
  end
  return out
end

local function Prune()
  local now, removed = GetTime(), false
  for name, m in pairs(Map.members) do
    if now - m.at >= EXPIRE then
      Map.members[name] = nil
      removed = true
    end
  end
  if removed then Changed() end
end

-- Only right after a roster update, since the cached roster goes stale between updates.
local function DropOffline()
  local now, removed = GetTime(), false
  for name, m in pairs(Map.members) do
    local info = ZR.RosterInfo(name)
    if info and info.online == false and now - m.at > 10 then
      Map.members[name] = nil
      removed = true
    end
  end
  if removed then Changed() end
end

local function OnMessage(_, prefix, text, channel, sender)
  if channel ~= "GUILD" or (prefix ~= PREFIX and prefix ~= MAPUTILS) then return end
  if ZR.IsSecret(text) or ZR.IsSecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
  local name = ZR.StripRealm(sender)
  if prefix == MAPUTILS then
    if text:sub(1, 1) ~= "G" then return end
    local mapID, x, y, class, level, _, taxi = strsplit(":", text:sub(2))
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return end
    Store(name, "MapUtils", tonumber(mapID), x / SCALE, y / SCALE, tonumber(level), class, taxi == "1")
    return
  end
  local proto, kind, mapID, x, y, level, class, taxi, instID, instKind, instName, playedSecs = strsplit("|", text)
  if proto ~= PROTO then return end
  if kind == "X" then
    Remove(name)
  elseif kind == "P" then
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return end
    instID = tonumber(instID)
    local instance = instID and instID > 0 and { id = instID, raid = instKind == "r", name = instName or "" } or nil
    Store(name, "zz", tonumber(mapID), x / SCALE, y / SCALE, tonumber(level), class, taxi == "1", instance,
      tonumber(playedSecs))
  end
end

function Map.SetSharing(on)
  ZR.DB().mapShare = on
  wipe(last)
  -- Turning it off clears our pin for everyone right away.
  if not on and IsInGuild() then Send(PROTO .. "|X") end
end

function Map.SetShowing(on)
  ZR.DB().mapPins = on
  Changed()
end

function Map.SetMinimap(on)
  ZR.DB().mapMinimap = on
  Changed()
end

function Map.Init()
  if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
  if C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    -- Members who only run MapUtils still show up.
    C_ChatInfo.RegisterAddonMessagePrefix(MAPUTILS)
  end
  ZR.RegisterEvent("CHAT_MSG_ADDON", OnMessage)
  C_Timer.NewTicker(SEND_EVERY, function()
    Broadcast()
    Prune()
  end)
  C_Timer.NewTicker(1, SampleOutside)
  C_Timer.After(2, Broadcast)
  C_Timer.After(8, RequestPlayed)
end

ZR.On("RosterChanged", DropOffline)
ZR.RegisterEvent("PLAYER_ENTERING_WORLD", EnterWorld)
ZR.RegisterEvent("PLAYER_LEAVING_WORLD", function()
  SampleOutside()
  leftAt = GetTime()
end)
ZR.RegisterEvent("CONFIRM_SUMMON", function() summonAt = GetTime() end)
-- Also catches a /played typed by the player.
ZR.RegisterEvent("TIME_PLAYED_MSG", function(_, total)
  if ZR.IsSecret(total) or type(total) ~= "number" then return end
  played = { total = total, at = GetTime() }
  -- Next frame, so this reply still skips the muted chat frames.
  C_Timer.After(0, Unmute)
end)
ZR.RegisterEvent("PLAYER_GUILD_UPDATE", function()
  wipe(Map.members)
  Changed()
end)
