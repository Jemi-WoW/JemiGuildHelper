local _, JGH = ...

-- Shares where guild members are, for the world map pins.
local Map = {}
JGH.Map = Map

local PREFIX = "JGHMap"
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
local ANSWER_COOLDOWN = 10

Map.members = {}
local last, lastOut = {}, {}
local inside, leftAt, summonAt, doors, doorsTriedAt, played, muted
local answerAt, answerTimer

function Map.Showing()
  return JGH.DB().mapPins ~= false
end

function Map.MinimapShowing()
  return JGH.DB().mapMinimap ~= false
end

-- Where to draw a member on their own map: gliding from the last spot over one send interval.
function Map.Position(m, now)
  local t = m.moveAt and ((now or GetTime()) - m.moveAt) / GLIDE or 1
  if t >= 1 then return m.x, m.y, false end
  return m.fromX + (m.x - m.fromX) * t, m.fromY + (m.y - m.fromY) * t, true
end

local function Changed()
  JGH.Fire("MapChanged")
end

local function Send(msg)
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
  return ok and (result == nil or result == true or result == 0)
end

local function CanSend()
  if not IsInGuild() then return false end
  if C_GuildInfo.CanSpeakInGuildChat and not C_GuildInfo.CanSpeakInGuildChat() then return false end
  local _, kind = IsInInstance()
  return kind ~= "pvp" and kind ~= "arena"
end

local function OwnPosition()
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID or JGH.IsSecret(mapID) then return end
  local pos = C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return end
  local x, y = pos:GetXY()
  if JGH.IsSecret(x) or JGH.IsSecret(y) or not x or not y or (x == 0 and y == 0) then return end
  return mapID, x, y
end
Map.OwnPosition = OwnPosition

local vec = CreateVector2D and CreateVector2D(0, 0)

-- World yards, which work across zone borders: x points north, y points west.
function Map.WorldPos(mapID, x, y)
  if not vec or not C_Map.GetWorldPosFromMapPos then return end
  vec:SetXY(x, y)
  local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, vec)
  if ok and continent and pos then return continent, pos.x, pos.y end
end

-- Only for instances the game has no entrance for.
local function WalkedIn()
  local db = JGH.DB()
  db.walkedIn = db.walkedIn or {}
  return db.walkedIn
end

local function AddDoor(map, key, door)
  map[key] = map[key] or {}
  table.insert(map[key], door)
end

-- The dungeon and raid entrances the game draws on its maps, by journal instance and by name.
local function Doors()
  if doors then return doors end
  local EJ = C_EncounterJournal
  if not EJ or not EJ.GetDungeonEntrancesForMap or not C_Map.GetMapChildrenInfo then return end
  if doorsTriedAt and GetTime() - doorsTriedAt < 60 then return end
  local byID, byName = {}, {}
  for _, root in ipairs({ 946, 947 }) do
    for _, zone in ipairs(C_Map.GetMapChildrenInfo(root, Enum.UIMapType.Zone, true) or {}) do
      local ok, list = pcall(EJ.GetDungeonEntrancesForMap, zone.mapID)
      for _, e in ipairs(ok and type(list) == "table" and list or {}) do
        if e.journalInstanceID and e.position then
          local x, y = e.position:GetXY()
          local door = { zone.mapID, x, y }
          AddDoor(byID, e.journalInstanceID, door)
          if type(e.name) == "string" and e.name ~= "" then AddDoor(byName, e.name:lower(), door) end
        end
      end
    end
    if next(byID) then break end
  end
  -- Map data can lag behind login, so an empty result is tried again later.
  if not next(byID) then
    doorsTriedAt = GetTime()
    return
  end
  doors = { byID = byID, byName = byName }
  return doors
end

-- Falls back to the name, or the longest entrance name it starts with, for wings named after their dungeon.
local function GameDoors(instanceID, name)
  local d = Doors()
  if not d then return end
  local get = C_EncounterJournal.GetInstanceForGameMap
  local ok, journalID = pcall(get or error, instanceID)
  if ok and journalID and not JGH.IsSecret(journalID) and d.byID[journalID] then return d.byID[journalID] end
  if type(name) ~= "string" or name == "" then return end
  name = name:lower()
  if d.byName[name] then return d.byName[name] end
  local best
  for doorName, list in pairs(d.byName) do
    if name:sub(1, #doorName) == doorName and (not best or #doorName > #best) then best = doorName end
  end
  return best and d.byName[best]
end

-- Some instances have more than one entrance; take the one nearest to where they went in.
local function Nearest(list, mapID, x, y)
  if #list == 1 or not mapID then return list[1] end
  local continent, wx, wy = Map.WorldPos(mapID, x, y)
  local best, bestDist
  for _, door in ipairs(list) do
    local c, dx, dy = Map.WorldPos(door[1], door[2], door[3])
    if continent and c == continent then
      local dist = (dx - wx) ^ 2 + (dy - wy) ^ 2
      if not bestDist or dist < bestDist then best, bestDist = door, dist end
    end
  end
  return best or list[1]
end

-- The game's own entrance wins over where someone happened to stand when the loading screen started.
local function Entrance(instanceID, name, mapID, x, y)
  if mapID and mapID <= 0 then mapID = nil end
  local list = GameDoors(instanceID, name)
  if list then
    local door = Nearest(list, mapID, x, y)
    return door[1], door[2], door[3]
  end
  if mapID then return mapID, x, y end
  local e = WalkedIn()[instanceID]
  if e then return e[1], e[2], e[3] end
end

local function InstanceKind()
  local isIn, kind = IsInInstance()
  if JGH.IsSecret(isIn) or JGH.IsSecret(kind) or not isIn then return end
  if kind == "party" or kind == "raid" then return kind end
end

-- Inside, members show at the instance's entrance.
local function EnterWorld(_, isLogin, isReload)
  inside = nil
  wipe(last)
  local kind = InstanceKind()
  if not kind then return end
  local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
  if JGH.IsSecret(name) or JGH.IsSecret(instanceID) or not instanceID then return end
  local now = GetTime()
  local walked = not isLogin and not isReload and lastOut.at and leftAt and leftAt - lastOut.at <= WALKED_IN
    and now - (summonAt or -SUMMON_WINDOW) > SUMMON_WINDOW
    and not (IsInLFGDungeon and IsInLFGDungeon())
  local mapID, x, y
  if walked then
    mapID, x, y = lastOut.mapID, lastOut.x, lastOut.y
    WalkedIn()[instanceID] = { mapID, x, y }
  end
  mapID, x, y = Entrance(instanceID, name, mapID, x, y)
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
local function Broadcast(force)
  if not CanSend() then return end
  local mapID, x, y
  if inside then
    mapID, x, y = inside.mapID, inside.x, inside.y
  else
    mapID, x, y = OwnPosition()
    if not mapID then return end
  end
  local onTaxi = UnitOnTaxi("player")
  local taxi = (not inside and not JGH.IsSecret(onTaxi) and onTaxi) and "1" or "0"
  local inst = inside and inside.id or 0
  local now = GetTime()
  local moved = last.mapID ~= mapID or last.taxi ~= taxi or last.inst ~= inst
    or math.abs(x - last.x) > MOVED or math.abs(y - last.y) > MOVED
  if not force and not moved and now - last.at < HEARTBEAT then return end
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

-- Members standing still only send every 30s, so someone logging in asks for every spot right away.
local function Ask()
  if IsInGuild() then Send(PROTO .. "|Q") end
end

local function Answer()
  if answerTimer or (answerAt and GetTime() - answerAt < ANSWER_COOLDOWN) then return end
  answerTimer = C_Timer.NewTimer(1 + math.random() * 3, function()
    answerTimer = nil
    answerAt = GetTime()
    Broadcast(true)
  end)
end

local function Remove(name)
  if Map.members[name] then
    Map.members[name] = nil
    Changed()
  end
end

local function Store(name, source, mapID, x, y, level, class, taxi, instance, playedSecs)
  if not name or name == "" or name == JGH.PlayerName() then return end
  if instance then
    mapID, x, y = Entrance(instance.id, instance.name, mapID, x, y)
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
    local info = JGH.RosterInfo(name)
    if info and info.online == false and now - m.at > 10 then
      Map.members[name] = nil
      removed = true
    end
  end
  if removed then Changed() end
end

local function OnMessage(_, prefix, text, channel, sender)
  if channel ~= "GUILD" or (prefix ~= PREFIX and prefix ~= MAPUTILS) then return end
  if JGH.IsSecret(text) or JGH.IsSecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
  local name = JGH.StripRealm(sender)
  if prefix == MAPUTILS then
    if text:sub(1, 1) ~= "G" then return end
    local mapID, x, y, class, level, _, taxi = strsplit(":", text:sub(2))
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return end
    Store(name, "MapUtils", tonumber(mapID), x / SCALE, y / SCALE, tonumber(level), class, taxi == "1")
    return
  end
  local proto, kind, mapID, x, y, level, class, taxi, instID, instKind, instName, playedSecs = strsplit("|", text)
  if proto ~= PROTO or name == JGH.PlayerName() then return end
  if kind == "X" then
    Remove(name)
  elseif kind == "Q" then
    Answer()
  elseif kind == "P" then
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return end
    instID = tonumber(instID)
    local instance = instID and instID > 0 and { id = instID, raid = instKind == "r", name = instName or "" } or nil
    Store(name, "zz", tonumber(mapID), x / SCALE, y / SCALE, tonumber(level), class, taxi == "1", instance,
      tonumber(playedSecs))
  end
end

function Map.SetShowing(on)
  JGH.DB().mapPins = on
  Changed()
end

function Map.SetMinimap(on)
  JGH.DB().mapMinimap = on
  Changed()
end

function Map.Init()
  -- Left over from when members could stop sharing.
  JGH.DB().mapShare = nil
  -- Guessed entrances from older versions, some of them wrong.
  JGH.DB().entrances = nil
  if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
  if C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    -- Members who only run MapUtils still show up.
    C_ChatInfo.RegisterAddonMessagePrefix(MAPUTILS)
  end
  JGH.RegisterEvent("CHAT_MSG_ADDON", OnMessage)
  C_Timer.NewTicker(SEND_EVERY, function()
    Broadcast()
    Prune()
  end)
  C_Timer.NewTicker(1, SampleOutside)
  C_Timer.After(2, Broadcast)
  C_Timer.After(8, RequestPlayed)
end

JGH.On("RosterChanged", DropOffline)
JGH.RegisterEvent("PLAYER_ENTERING_WORLD", EnterWorld)
JGH.RegisterEvent("PLAYER_LEAVING_WORLD", function()
  SampleOutside()
  leftAt = GetTime()
end)
JGH.RegisterEvent("CONFIRM_SUMMON", function() summonAt = GetTime() end)
-- Also catches a /played typed by the player.
JGH.RegisterEvent("TIME_PLAYED_MSG", function(_, total)
  if JGH.IsSecret(total) or type(total) ~= "number" then return end
  played = { total = total, at = GetTime() }
  -- Next frame, so this reply still skips the muted chat frames.
  C_Timer.After(0, Unmute)
end)
JGH.On("GuildReady", function() C_Timer.After(3, Ask) end)
-- Also fires on rank changes, which shouldn't blank the map.
JGH.RegisterEvent("PLAYER_GUILD_UPDATE", function()
  if IsInGuild() or not next(Map.members) then return end
  wipe(Map.members)
  Changed()
end)
