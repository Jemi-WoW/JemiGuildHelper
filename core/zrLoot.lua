local _, ZR = ...

-- Roll-offs for raid loot: the leader starts one, everyone rolls, reserves decide who may.
local Loot = {}
ZR.Loot = Loot

local PREFIX = "ZUGZUGLoot"
local PROTO = "1"
local DURATION = 30
Loot.DURATIONS = { 10, 20, 30 }
local GRACE = 3
local MAIN, OFF = 100, 99
local RAID_BEFORE, RAID_AFTER = 2 * 3600, 8 * 3600

Loot.test = false
Loot.session = nil

local rollPattern
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function B36(n)
  n = math.floor(n or 0)
  local s = ""
  repeat
    local r = n % 36
    s = DIGITS:sub(r + 1, r + 1) .. s
    n = math.floor(n / 36)
  until n <= 0
  return s
end

local function Me()
  return ZR.PlayerName()
end

-- Built from the game's own "%s rolls %d (%d-%d)" so other languages match too.
local function RollPattern()
  if rollPattern then return rollPattern end
  local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
  local p = fmt:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
  p = p:gsub("%%%%%d?%$?s", "(.+)"):gsub("%%%%%d?%$?d", "(%%d+)")
  rollPattern = "^" .. p .. "$"
  return rollPattern
end
Loot.RollPattern = RollPattern

local function Channel()
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
end

local function Send(msg)
  local channel = Channel()
  if not channel then return end
  pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel)
end

local function Icons(text)
  return (text:gsub("{rt(%d)}", "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%1:0|t"))
end

-- Raid warning when allowed, else raid or party chat; alone it shows on your own screen only.
local function Say(text)
  if not IsInGroup() then
    if RaidNotice_AddMessage and RaidWarningFrame then
      RaidNotice_AddMessage(RaidWarningFrame, Icons(text), ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.3, b = 0 })
    end
    ZR.Msg(Icons(text))
    return
  end
  local lead = UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
  local channel = (IsInRaid() and not lead and "RAID") or (not IsInRaid() and not lead and "PARTY") or "RAID_WARNING"
  ZR.SendChat(text, channel)
end

local function MasterLooter()
  if not (C_PartyInfo and C_PartyInfo.GetLootMethod) then return end
  local ok, method, partyID, raidID = pcall(C_PartyInfo.GetLootMethod)
  if not ok or not Enum.LootMethod or method ~= Enum.LootMethod.Masterlooter then return end
  if raidID then return ZR.StripRealm(UnitName("raid" .. raidID)) end
  if partyID == 0 then return Me() end
  if partyID then return ZR.StripRealm(UnitName("party" .. partyID)) end
end

function Loot.CanLead()
  if Loot.test then return true end
  if not IsInGroup() then return false end
  return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") or MasterLooter() == Me()
end

-- Only the people running the raid may start rolls for everyone.
local function Trusted(sender)
  if Loot.test then return true end
  return UnitIsGroupLeader(sender) or UnitIsGroupAssistant(sender) or MasterLooter() == sender
end

-- The planned raid you're inside right now: started up to 8 hours ago or starting within 2.
function Loot.CurrentRaid()
  local now, best = ZR.Now(), nil
  for _, ev in ipairs(ZR.Raids.List()) do
    if ev.start <= now + RAID_BEFORE and ev.start >= now - RAID_AFTER and (not best or ev.start > best.start)
      and ZR.Raids.InsideRaid(ev.raid) then best = ev end
  end
  return best
end

-- Hard beats soft; test mode lets reserves on the temp item stand in for whatever you loot.
function Loot.ReservesFor(itemID)
  local ev = Loot.CurrentRaid()
  if not ev then return "O", {} end
  local hard, soft, seen = {}, {}, {}
  local function Scan(id)
    for _, r in ipairs(ZR.Raids.Reserves(ev)) do
      if r.i == id and not seen[r.k .. r.n] then
        seen[r.k .. r.n] = true
        local list = r.k == "H" and hard or soft
        list[#list + 1] = r.n
      end
    end
  end
  Scan(itemID)
  if Loot.test and #hard == 0 and #soft == 0 then Scan(ZR.Raids.TEMP_ITEM) end
  if #hard > 0 then return "H", hard, ev end
  if #soft > 0 then return "S", soft, ev end
  return "O", {}, ev
end

local function Finish(s)
  if s.ended then return end
  s.ended = true
  if s.timer then s.timer:Cancel() end
  ZR.Fire("LootEnd", s)
end

local function Begin(s)
  if Loot.session and not Loot.session.ended then Finish(Loot.session) end
  s.allow = {}
  for _, name in ipairs(s.names) do s.allow[name:lower()] = true end
  s.rolls, s.rolled = {}, {}
  s.startedAt = GetTime()
  s.endAt = s.startedAt + s.dur
  Loot.session = s
  if s.mode == "H" then
    s.ended = true
  else
    s.timer = C_Timer.NewTimer(s.dur, function() Finish(s) end)
  end
  ZR.Fire("LootStart", s)
end

function Loot.IsLeader(s)
  s = s or Loot.session
  return s and s.starter == Me()
end

function Loot.Duration()
  return ZR.DB().rollTime or DURATION
end

-- link is any item link, from the loot window or chat; dur is in seconds.
function Loot.Start(link, dur)
  if not Loot.CanLead() then
    ZR.Msg("Only the raid leader, an assistant or the master looter can start a roll.")
    return
  end
  if Loot.session and not Loot.session.ended then
    ZR.Msg("A roll is still running. End it first.")
    return
  end
  local itemID = link and tonumber(link:match("item:(%d+)"))
  if not itemID then return end
  dur = dur or Loot.Duration()
  local mode, names = Loot.ReservesFor(itemID)
  local list = table.concat(names, ","):gsub("[|:]", "")
  local who = table.concat(names, ", ")
  local id = B36(GetServerTime()) .. B36(math.random(0, 1295))
  Send(table.concat({ PROTO, "S", id, itemID, dur, mode, list:sub(1, 180) }, "|"))
  if mode == "H" then
    Say(("{rt2} HARD RESERVE: %s goes to %s {rt2}"):format(link, who))
  elseif mode == "S" then
    Say(("{rt3} SOFT RESERVE ROLL: %s {rt3}"):format(link))
    Say(("Only %s may /roll - %d seconds"):format(who, dur))
  else
    Say(("{rt1} ROLL: %s {rt1}"):format(link))
    Say(("/roll for main spec - /roll 99 for off spec - %d seconds"):format(dur))
  end
  Begin({ id = id, itemID = itemID, link = link, mode = mode, names = names, dur = dur, starter = Me() })
end

function Loot.Stop()
  local s = Loot.session
  if not s or s.ended or not Loot.IsLeader(s) then return end
  Send(table.concat({ PROTO, "E", s.id }, "|"))
  Say(("{rt7} Rolls closed for %s {rt7}"):format(s.link or "the item"))
  Finish(s)
end

-- Valid rolls first, main spec over off spec, highest first; the rest after.
function Loot.Ranked(s)
  s = s or Loot.session
  if not s then return {}, nil, false end
  local list = {}
  for _, r in ipairs(s.rolls) do list[#list + 1] = r end
  local function Rank(r)
    if not r.valid then return 0 end
    return r.kind == "MS" and 2 or 1
  end
  table.sort(list, function(a, b)
    local ra, rb = Rank(a), Rank(b)
    if ra ~= rb then return ra > rb end
    if a.roll ~= b.roll then return a.roll > b.roll end
    return a.at < b.at
  end)
  local top, second = list[1], list[2]
  local winner = top and top.valid and top or nil
  local tie = winner and second and second.valid and second.kind == winner.kind and second.roll == winner.roll or false
  return list, winner, tie
end

function Loot.AnnounceWinner()
  local s = Loot.session
  if not s or not Loot.IsLeader(s) then return end
  local link = s.link or ("item:" .. s.itemID)
  local list, winner, tie = Loot.Ranked(s)
  if not winner then
    Say(("{rt7} Nobody rolled for %s {rt7}"):format(link))
  elseif tie then
    local names = {}
    for _, r in ipairs(list) do
      if r.valid and r.kind == winner.kind and r.roll == winner.roll then names[#names + 1] = r.name end
    end
    Say(("{rt8} TIE on %s: %s rolled %d - roll again! {rt8}"):format(link, table.concat(names, " and "), winner.roll))
  else
    Say(("{rt1} WINNER: %s wins %s with %d (%s) {rt1}"):format(winner.name, link, winner.roll,
      winner.kind == "MS" and "main spec" or "off spec"))
  end
end

function Loot.CanRoll(s)
  s = s or Loot.session
  if not s or s.ended or s.mode == "H" then return false end
  return s.mode == "O" or s.allow[Me():lower()] == true
end

-- Rolls come from the game's /roll messages, so players without the addon count too.
local function OnSystem(_, text)
  local s = Loot.session
  if not s or s.mode == "H" or ZR.IsSecret(text) or type(text) ~= "string" then return end
  if s.ended and GetTime() > s.endAt + GRACE then return end
  local who, roll, low, high = text:match(RollPattern())
  roll, low, high = tonumber(roll), tonumber(low), tonumber(high)
  if not who or not roll then return end
  who = ZR.StripRealm(who)
  local me = Me()
  if IsInGroup() then
    if who ~= me and not UnitInRaid(who) and not UnitInParty(who) then return end
  elseif who ~= me then
    return
  end
  local kind = (low == 1 and high == MAIN and "MS") or (low == 1 and high == OFF and "OS") or nil
  local r = { name = who, roll = roll, range = low .. "-" .. high, kind = kind, at = GetTime() }
  r.again = s.rolled[who]
  r.allowed = s.mode == "O" or s.allow[who:lower()] == true
  r.valid = kind ~= nil and r.allowed and not r.again
  local _, class = UnitClass(who)
  if not class then
    local info = ZR.RosterInfo(who)
    class = info and info.classFile
  end
  r.class = class
  s.rolled[who] = true
  s.rolls[#s.rolls + 1] = r
  ZR.Fire("LootRoll", s, r)
end

local function OnAddon(_, prefix, text, channel, sender)
  if prefix ~= PREFIX or ZR.IsSecret(text) or ZR.IsSecret(sender) then return end
  sender = ZR.StripRealm(sender)
  if sender == Me() then return end
  local f = { strsplit("|", text) }
  if f[1] ~= PROTO then return end
  if f[2] == "S" and Trusted(sender) then
    local names = {}
    for name in (f[7] or ""):gmatch("[^,]+") do names[#names + 1] = name end
    Begin({ id = f[3], itemID = tonumber(f[4]), dur = tonumber(f[5]) or DURATION, mode = f[6] or "O", names = names, starter = sender })
  elseif f[2] == "E" and Loot.session and Loot.session.id == f[3] and Trusted(sender) then
    Finish(Loot.session)
  end
end

function Loot.SetTest(on)
  Loot.test = on
  ZR.Fire("LootTestChanged", on)
end

function Loot.Init()
  if C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
  ZR.RegisterEvent("CHAT_MSG_ADDON", OnAddon)
  ZR.RegisterEvent("CHAT_MSG_SYSTEM", OnSystem)
end
