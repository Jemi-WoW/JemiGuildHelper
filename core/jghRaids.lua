local _, JGH = ...

-- Raid events and sign-ups, shared with every guild member running the addon.
local Raids = {}
JGH.Raids = Raids

local PREFIX = "JGHRaid"
local PROTO = "1"
local BURST = 6
local MAX_QUEUE = 800
local DESC_CHUNK = 180
local DESC_MAX = 360
local NOTE_MAX = 40
local TITLE_MAX = 40
local DONE_AFTER = 12 * 3600
local KEEP_ARCHIVE = 60 * 86400
local KEEP_DELETED = 14 * 86400
local ASK_GAP = 30
local ASK_EVERY = 600
local DIGEST_PART = 200
local REMIND_AT = { 30, 20, 15, 10, 5 }

-- WoW Forever's raids; sizes are fixed per raid, Other covers anything else.
Raids.LIST = {
-- Entrances: Onyxia from the game's own data, the two Hyjal raids from guides until they open.
  { key = "barrow", name = "Barrow Deeps", size = 10, where = "Mount Hyjal", icon = "Interface\\Icons\\Spell_Nature_Sleep",
    map = 2482, x = 0.70, y = 0.62 },
  { key = "hyjal", name = "Hyjal Summit", size = 20, where = "Mount Hyjal", icon = "Interface\\Icons\\Spell_Nature_Tranquility",
    map = 2482, x = 0.85, y = 0.33, zones = { "The Battle for Mount Hyjal" } },
  { key = "onyxia", name = "Onyxia's Lair", size = 40, where = "Dustwallow Marsh", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black",
    map = 1445, x = 0.526, y = 0.768, instance = 249, note = "Every raider needs the Drakefire Amulet." },
  { key = "other", name = "Other", size = 20, icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
}
Raids.SIZES = { 10, 20, 40 }
Raids.DESC_MAX = DESC_MAX
-- Tanks and healers to aim for per size; officers can change them per raid.
Raids.TARGETS = { [10] = { 2, 3 }, [20] = { 3, 5 }, [40] = { 3, 10 } }

Raids.ROLES = { "T", "H", "M", "R" }
Raids.ROLE_NAMES = { T = "Tank", H = "Healer", M = "Melee", R = "Ranged" }
Raids.ROLE_ICONS = {
  T = "Interface\\Icons\\Ability_Defend",
  H = "Interface\\Icons\\Spell_Holy_FlashHeal",
  M = "Interface\\Icons\\INV_Sword_04",
  R = "Interface\\Icons\\INV_Weapon_Bow_02",
}
-- Roles per class on Forever, first one is the default; classes not listed may take any role.
Raids.CLASS_ROLES = {
  WARRIOR = "TM", PALADIN = "THM", HUNTER = "RM", ROGUE = "M", PRIEST = "HR",
  SHAMAN = "HMR", MAGE = "R", WARLOCK = "R", DRUID = "THMR",
}
Raids.STATUS_NAMES = { ["in"] = "Signed up", late = "Late", tent = "Tentative", bench = "Bench", absent = "Absent" }

local queue, tokens = {}, BURST
local pendingDesc, replying, queries = {}, {}, {}
local lastAsk = -math.huge
local reminded = {}

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function B36(n)
  n = math.floor(n or 0)
  if n <= 0 then return "0" end
  local s = ""
  while n > 0 do
    local r = n % 36
    s = DIGITS:sub(r + 1, r + 1) .. s
    n = math.floor(n / 36)
  end
  return s
end

local function Clean(s, max)
  s = tostring(s or ""):gsub("|", "/"):gsub("[\r\n]+", " ")
  return strtrim(s):sub(1, max)
end

local function Store()
  local g = JGH.GDB()
  if not g then return nil end
  g.raids = g.raids or {}
  return g.raids
end
Raids.Store = Store

local function Changed()
  JGH.Fire("RaidsChanged")
end

function Raids.Info(key)
  for _, r in ipairs(Raids.LIST) do
    if r.key == key then return r end
  end
  return Raids.LIST[#Raids.LIST]
end

-- Matched by instance ID when known, else by the instance's name; Other counts any raid instance.
function Raids.InsideRaid(key)
  local name, kind, _, _, _, _, _, instanceID = GetInstanceInfo()
  if JGH.IsSecret(name) or JGH.IsSecret(kind) or kind ~= "raid" then return false end
  local r = Raids.Info(key)
  if r.key == "other" then return true end
  if r.instance and r.instance == instanceID then return true end
  name = (name or ""):lower()
  if name == r.name:lower() then return true end
  for _, zone in ipairs(r.zones or {}) do
    if name == zone:lower() then return true end
  end
  return false
end

function Raids.Title(ev)
  if ev.title and ev.title ~= "" then return ev.title end
  return Raids.Info(ev.raid).name
end

-- 12 or 24 hour times; follows the game clock's setting until picked here.
function Raids.Use12h()
  local pick = JGH.DB().raidClock
  if pick then return pick == 12 end
  return GetCVarBool and not GetCVarBool("timeMgrUseMilitaryTime") or false
end

function Raids.SetClock(hours)
  JGH.DB().raidClock = hours
  Changed()
end

function Raids.Time(ts)
  local t = date("*t", ts)
  if not Raids.Use12h() then return ("%02d:%02d"):format(t.hour, t.min) end
  return ("%d:%02d %s"):format((t.hour - 1) % 12 + 1, t.min, t.hour < 12 and "AM" or "PM")
end

function Raids.When(ts, long)
  return date(long and "%A %d %B" or "%a %d %b", ts) .. ", " .. Raids.Time(ts)
end

function Raids.RolesFor(class)
  return Raids.CLASS_ROLES[class or ""] or "THMR"
end

function Raids.CanRole(class, role)
  return Raids.RolesFor(class):find(role, 1, true) ~= nil
end

function Raids.Get(id)
  local store = Store()
  local ev = store and store[id]
  if ev and (ev.v or 0) > 0 and not ev.del then return ev end
end

-- Sign-ups close when the raid starts; officers can still sort people after that.
function Raids.IsOpen(ev)
  return not ev.closed and not Raids.IsArchived(ev) and (ev.start or 0) > JGH.Now()
end

-- Archived by an officer, or done: half a day after it started.
function Raids.IsArchived(ev)
  return ev.arch or (ev.start or 0) + DONE_AFTER <= JGH.Now()
end

local function Collect(archived)
  local out, now = {}, JGH.Now()
  for _, ev in pairs(Store() or {}) do
    if (ev.v or 0) > 0 and not ev.del and (ev.start or 0) + KEEP_ARCHIVE > now and (Raids.IsArchived(ev) and true or false) == archived then
      out[#out + 1] = ev
    end
  end
  return out
end

-- Soonest first.
function Raids.List()
  local out = Collect(false)
  table.sort(out, function(a, b) return a.start < b.start end)
  return out
end

-- Newest first.
function Raids.Archived()
  local out = Collect(true)
  table.sort(out, function(a, b) return a.start > b.start end)
  return out
end

-- Everyone signed in sign-up order, numbered like the Discord bot does it.
function Raids.Signups(ev)
  local list = {}
  for name, s in pairs(ev.signups or {}) do
    if s.st ~= "x" then list[#list + 1] = { name = name, s = s } end
  end
  table.sort(list, function(a, b)
    if (a.s.at or 0) ~= (b.s.at or 0) then return (a.s.at or 0) < (b.s.at or 0) end
    return a.name < b.name
  end)
  for i, e in ipairs(list) do e.n = i end
  return list
end

function Raids.Counts(ev)
  local c = { T = 0, H = 0, M = 0, R = 0, going = 0 }
  for _, s in pairs(ev.signups or {}) do
    if s.st == "in" or s.st == "late" then
      c[s.role] = (c[s.role] or 0) + 1
      c.going = c.going + 1
    end
  end
  return c
end

-- Officer reserves plus the soft reserves players picked themselves.
function Raids.Reserves(ev, name)
  local out = {}
  for _, r in ipairs(ev.res or {}) do
    if not name or r.n == name then out[#out + 1] = r end
  end
  for who, s in pairs(ev.signups or {}) do
    if s.sr and s.st ~= "x" and s.st ~= "absent" and (not name or who == name) then
      for _, r in ipairs(s.sr) do out[#out + 1] = { k = "S", i = r.i, b = r.b, n = who, own = true } end
    end
  end
  return out
end

function Raids.SoftLimit(ev)
  return ev.srMax or 1
end

function Raids.SoftUsed(ev, name)
  local n = 0
  for _, r in ipairs(Raids.Reserves(ev, name)) do
    if r.k == "S" then n = n + 1 end
  end
  return n
end

function Raids.Mine(ev)
  local s = ev.signups and ev.signups[JGH.PlayerName()]
  if s and s.st ~= "x" then return s end
end

local function Queue(msg)
  if msg and #queue < MAX_QUEUE then queue[#queue + 1] = msg end
end

local function Send(msg)
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
  if not ok then return true end
  -- 3 and 8 are throttles and 11 is a combat lockdown; those retry.
  return result ~= 3 and result ~= 8 and result ~= 11
end

local function Pump()
  tokens = math.min(BURST, tokens + 1)
  while tokens >= 1 and #queue > 0 do
    if not IsInGuild() then
      wipe(queue)
      break
    end
    if not Send(queue[1]) then break end
    table.remove(queue, 1)
    tokens = tokens - 1
  end
end

local function Join(...)
  return table.concat({ PROTO, ... }, "|")
end

local function EscapeDesc(s)
  return (s:gsub("\\", "/"):gsub("|", "/"):gsub("\r?\n", "\\n"))
end

-- Reserves as "kind:item:boss:name" entries, packed into as few messages as fit.
local function ReserveChunks(ev)
  local chunks, buf, len = {}, {}, 0
  for _, r in ipairs(ev.res or {}) do
    local entry = table.concat({ r.k, r.i, r.b, r.n }, ":")
    if len + #entry + 1 > DESC_CHUNK and #buf > 0 then
      chunks[#chunks + 1] = table.concat(buf, ";")
      buf, len = {}, 0
    end
    buf[#buf + 1] = entry
    len = len + #entry + 1
  end
  if #buf > 0 then chunks[#chunks + 1] = table.concat(buf, ";") end
  return chunks
end

local function QueueEvent(ev)
  local desc = EscapeDesc(ev.desc or "")
  local chunks = {}
  for i = 1, #desc, DESC_CHUNK do chunks[#chunks + 1] = desc:sub(i, i + DESC_CHUNK - 1) end
  local res = ReserveChunks(ev)
  Queue(Join("E", ev.id, ev.v, ev.del and 1 or 0, ev.raid or "", ev.size or 0, ev.start or 0, ev.leader or "",
    ev.by or "", ev.tanks or 0, ev.healers or 0, ev.closed and 1 or 0, ev.title or "", #chunks, ev.arch and 1 or 0, #res, ev.srMax or 1))
  for i, chunk in ipairs(chunks) do Queue(Join("D", ev.id, ev.v, i, #chunks, chunk)) end
  for i, chunk in ipairs(res) do Queue(Join("L", ev.id, ev.v, i, #res, chunk)) end
end

-- A player's own soft reserves ride along with their sign-up as "item:boss;item:boss".
local function EncodeSoft(list)
  local parts = {}
  for _, r in ipairs(list or {}) do parts[#parts + 1] = r.i .. ":" .. r.b end
  return table.concat(parts, ";")
end

local function DecodeSoft(text)
  local out = {}
  for entry in (text or ""):gmatch("[^;]+") do
    local item, boss = entry:match("^(%d+):(.*)$")
    if item then out[#out + 1] = { i = tonumber(item), b = boss } end
  end
  return #out > 0 and out or nil
end

local function QueueSignup(id, name, s)
  Queue(Join("S", id, name, s.v, s.st, s.role or "", s.c or "", s.at or 0, s.note or "", EncodeSoft(s.sr), s.g and 1 or ""))
end

local function QueueSignups(ev)
  for name, s in pairs(ev.signups or {}) do QueueSignup(ev.id, name, s) end
end

-- Count and summed versions; equal on both sides means the same sign-ups.
local function Sig(ev)
  local n, sum = 0, 0
  for _, s in pairs(ev.signups or {}) do
    n = n + 1
    sum = (sum + (s.v or 0)) % 1000000007
  end
  return n, sum
end

local function Stamp(old)
  return math.max(JGH.Now(), (old or 0) + 1)
end

local function MergeEvent(f)
  local store = Store()
  if not store then return end
  local id, v = f[3], tonumber(f[4]) or 0
  if not id or id == "" or v <= 0 then return end
  local ev = store[id]
  if ev and (ev.v or 0) >= v then return end
  ev = ev or { id = id, signups = {} }
  store[id] = ev
  ev.v, ev.del = v, f[5] == "1" or nil
  ev.raid, ev.size, ev.start = f[6], tonumber(f[7]) or 0, tonumber(f[8]) or 0
  ev.leader, ev.by = f[9], f[10]
  ev.tanks, ev.healers = tonumber(f[11]) or 0, tonumber(f[12]) or 0
  ev.closed = f[13] == "1" or nil
  ev.title = f[14] or ""
  ev.arch = f[16] == "1" or nil
  if (tonumber(f[15]) or 0) == 0 then ev.desc = "" end
  if (tonumber(f[17]) or 0) == 0 then ev.res = nil end
  ev.srMax = tonumber(f[18])
  Changed()
end

local function MergeDesc(id, v, i, n, chunk)
  local store = Store()
  if not store or not id or not v or not i or not n then return end
  local key = id .. "|" .. v
  local part = pendingDesc[key] or { got = 0, parts = {} }
  pendingDesc[key] = part
  if not part.parts[i] then
    part.parts[i] = chunk or ""
    part.got = part.got + 1
  end
  if part.got < n then return end
  pendingDesc[key] = nil
  local ev = store[id]
  if not ev or ev.v ~= v then return end
  ev.desc = table.concat(part.parts, "", 1, n):gsub("\\n", "\n")
  Changed()
end

local function MergeReserves(id, v, i, n, chunk)
  local store = Store()
  if not store or not id or not v or not i or not n then return end
  local key = id .. "|" .. v .. "|res"
  local part = pendingDesc[key] or { got = 0, parts = {} }
  pendingDesc[key] = part
  if not part.parts[i] then
    part.parts[i] = chunk or ""
    part.got = part.got + 1
  end
  if part.got < n then return end
  pendingDesc[key] = nil
  local ev = store[id]
  if not ev or ev.v ~= v then return end
  local res = {}
  for entry in table.concat(part.parts, ";", 1, n):gmatch("[^;]+") do
    local k, item, boss, name = strsplit(":", entry)
    item = tonumber(item)
    if (k == "S" or k == "H") and item and name and name ~= "" then res[#res + 1] = { k = k, i = item, b = boss or "", n = name } end
  end
  ev.res = res
  Changed()
end

local function MergeSignup(f)
  local store = Store()
  if not store then return end
  local id, name, v = f[3], f[4], tonumber(f[5]) or 0
  if not id or id == "" or not name or name == "" or v <= 0 then return end
  local ev = store[id]
  -- Sign-ups can beat their event here; a stub holds them until it arrives.
  if not ev then
    ev = { id = id, v = 0, signups = {} }
    store[id] = ev
  end
  local old = ev.signups[name]
  if old and (old.v or 0) >= v then return end
  local at = tonumber(f[9]) or 0
  if old and (old.at or 0) > 0 and old.at < at then at = old.at end
  ev.signups[name] = { v = v, st = f[6], role = f[7] ~= "" and f[7] or nil, c = f[8] ~= "" and f[8] or nil, at = at, note = f[10] or "",
    sr = DecodeSoft(f[11]), g = f[12] == "1" or nil }
  Changed()
end

-- Everything we hold, split over as many messages as it takes.
local function Digest()
  local parts, buf, len = {}, {}, 0
  for _, ev in pairs(Store() or {}) do
    if (ev.v or 0) > 0 then
      local n, sum = Sig(ev)
      local entry = table.concat({ ev.id, B36(ev.v), n, B36(sum) }, ":")
      if len + #entry + 1 > DIGEST_PART then
        parts[#parts + 1] = table.concat(buf, ";")
        buf, len = {}, 0
      end
      buf[#buf + 1] = entry
      len = len + #entry + 1
    end
  end
  parts[#parts + 1] = table.concat(buf, ";")
  return parts
end

function Raids.Ask()
  if not IsInGuild() or not Store() or GetTime() - lastAsk < ASK_GAP then return end
  lastAsk = GetTime()
  local qid = B36(math.random(0, 46655))
  local parts = Digest()
  for i, part in ipairs(parts) do Queue(Join("Q", qid, i, #parts, part)) end
end

-- A short random wait lets one member answer; hearing someone else's answer cancels ours.
local function Reply(ev, header, signups)
  if replying[ev.id] then return end
  replying[ev.id] = C_Timer.NewTimer(1 + math.random() * 4, function()
    replying[ev.id] = nil
    if header then QueueEvent(ev) end
    if signups then QueueSignups(ev) end
  end)
end

local function HeardAnswer(id)
  if replying[id] then
    replying[id]:Cancel()
    replying[id] = nil
  end
end

local function OnQuery(list)
  local theirs = {}
  for entry in (list or ""):gmatch("[^;]+") do
    local id, v, n, sum = strsplit(":", entry)
    if id then theirs[id] = { v = tonumber(v or "", 36) or 0, n = tonumber(n) or 0, sum = tonumber(sum or "", 36) or 0 } end
  end
  local now, askBack = JGH.Now(), false
  for id, ev in pairs(Store() or {}) do
    if (ev.v or 0) > 0 and (ev.start or 0) + KEEP_ARCHIVE > now then
      local t = theirs[id]
      local n, sum = Sig(ev)
      local header = not t or t.v < ev.v
      local signups = not t or t.n ~= n or t.sum ~= sum
      if header or signups then Reply(ev, header, signups) end
      if t and (t.v > ev.v or signups) then askBack = true end
    end
  end
  for id in pairs(theirs) do
    local ev = Store()[id]
    if not ev or (ev.v or 0) == 0 then askBack = true end
  end
  if askBack then C_Timer.After(6 + math.random() * 4, Raids.Ask) end
end

-- A digest can span several messages; it is only compared once all parts are in.
local function OnQueryPart(sender, qid, i, n, list)
  local now = GetTime()
  for key, q in pairs(queries) do
    if now - q.at > 30 then queries[key] = nil end
  end
  if not i or not n or n < 1 or n > 50 then return end
  local key = sender .. "|" .. qid
  local q = queries[key] or { got = 0, parts = {}, at = now }
  queries[key] = q
  if not q.parts[i] then
    q.parts[i] = list or ""
    q.got = q.got + 1
  end
  if q.got < n then return end
  queries[key] = nil
  OnQuery(table.concat(q.parts, ";", 1, n))
end

local function OnMessage(_, prefix, text, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" then return end
  if JGH.IsSecret(text) or JGH.IsSecret(sender) or not Store() then return end
  if JGH.StripRealm(sender) == JGH.PlayerName() then return end
  local f = { strsplit("|", text) }
  if f[1] ~= PROTO then return end
  local kind = f[2]
  if kind == "E" then
    HeardAnswer(f[3])
    MergeEvent(f)
  elseif kind == "D" then
    MergeDesc(f[3], tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), f[7])
  elseif kind == "L" then
    MergeReserves(f[3], tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), f[7])
  elseif kind == "S" then
    HeardAnswer(f[3])
    MergeSignup(f)
  elseif kind == "Q" then
    OnQueryPart(sender, f[3] or "", tonumber(f[4]), tonumber(f[5]), f[6])
  end
end

-- Officers only: create when fields.id is missing, otherwise edit.
function Raids.Save(fields)
  local store = Store()
  if not store or not JGH.IsOfficer() then return end
  local ev = fields.id and store[fields.id]
  if not ev then
    ev = { id = B36(JGH.Now()) .. B36(math.random(0, 46655)), signups = {}, by = JGH.PlayerName() }
    store[ev.id] = ev
  end
  ev.v = Stamp(ev.v)
  ev.del = nil
  ev.raid = fields.raid
  ev.size = fields.size
  ev.start = fields.start
  ev.leader = Clean(fields.leader, 40)
  ev.tanks = fields.tanks or 0
  ev.healers = fields.healers or 0
  ev.title = Clean(fields.title, TITLE_MAX)
  ev.desc = strtrim(((fields.desc or ""):gsub("|", "/"))):sub(1, DESC_MAX)
  ev.srMax = fields.srMax or 1
  ev.res = {}
  for _, r in ipairs(fields.res or {}) do
    ev.res[#ev.res + 1] = { k = r.k, i = r.i, b = Clean(r.b, 40):gsub("[:;]", ""), n = Clean(r.n, 40):gsub("[:;]", "") }
  end
  QueueEvent(ev)
  Changed()
  return ev.id
end

function Raids.Delete(id)
  local ev = Raids.Get(id)
  if not ev or not JGH.IsOfficer() then return end
  ev.v = Stamp(ev.v)
  ev.del = true
  QueueEvent(ev)
  Changed()
end

-- Archived raids keep their sign-ups and can be restored.
function Raids.SetArchived(id, archived)
  local ev = Raids.Get(id)
  if not ev or not JGH.IsOfficer() then return end
  ev.v = Stamp(ev.v)
  ev.arch = archived or nil
  QueueEvent(ev)
  Changed()
end

function Raids.SetClosed(id, closed)
  local ev = Raids.Get(id)
  if not ev or not JGH.IsOfficer() then return end
  ev.v = Stamp(ev.v)
  ev.closed = closed or nil
  QueueEvent(ev)
  Changed()
end

-- Players change their own sign-up; officers may change anyone's. extra.c and extra.g add a guest from outside the guild.
function Raids.SetSignup(id, name, st, role, note, extra)
  local ev = Raids.Get(id)
  if not ev then return end
  local me = JGH.PlayerName()
  name = name or me
  if name ~= me and not JGH.IsOfficer() then return end
  if name == me and not Raids.IsOpen(ev) and not JGH.IsOfficer() then return end
  local old = ev.signups[name]
  local class = (extra and extra.c) or (old and old.c)
  if name == me then class = select(2, UnitClass("player")) end
  if not class then
    local info = JGH.RosterInfo(name)
    class = info and info.classFile
  end
  local s = {
    v = Stamp(old and old.v),
    st = st,
    role = role or (old and old.role),
    c = class,
    note = note and Clean(note, NOTE_MAX) or (old and old.note) or "",
    at = (old and old.st ~= "x" and old.at) or JGH.Now(),
    -- Leaving the raid drops your soft reserves with it.
    sr = st ~= "x" and old and old.sr or nil,
    g = (extra and extra.g) or (old and old.g) or nil,
  }
  if not s.role or not Raids.CanRole(class, s.role) then s.role = Raids.RolesFor(class):sub(1, 1) end
  ev.signups[name] = s
  if name == me then JGH.CharDB().raidRole = s.role end
  QueueSignup(id, name, s)
  Changed()
end

local function SetOwnSoft(ev, list)
  local me = JGH.PlayerName()
  local old = ev.signups[me]
  local s = {}
  for k, v in pairs(old) do s[k] = v end
  s.v = Stamp(old.v)
  s.sr = #list > 0 and list or nil
  ev.signups[me] = s
  QueueSignup(ev.id, me, s)
  Changed()
end

-- Players soft reserve for themselves once signed up, up to the raid's limit.
function Raids.AddSoftReserve(id, item, boss)
  local ev = Raids.Get(id)
  local mine = ev and Raids.Mine(ev)
  if not mine or mine.st == "absent" or not Raids.IsOpen(ev) then return end
  if Raids.SoftUsed(ev, JGH.PlayerName()) >= Raids.SoftLimit(ev) then return end
  local list = {}
  for _, r in ipairs(mine.sr or {}) do
    if r.i == item and r.b == boss then return end
    list[#list + 1] = r
  end
  list[#list + 1] = { i = item, b = (tostring(boss or ""):gsub("[|:;]", "")) }
  SetOwnSoft(ev, list)
end

function Raids.RemoveSoftReserve(id, index)
  local ev = Raids.Get(id)
  local mine = ev and Raids.Mine(ev)
  if not mine or not mine.sr then return end
  local list = {}
  for i, r in ipairs(mine.sr) do
    if i ~= index then list[#list + 1] = r end
  end
  SetOwnSoft(ev, list)
end

function Raids.LastRole(class)
  local role = JGH.CharDB().raidRole
  if role and Raids.CanRole(class, role) then return role end
  return Raids.RolesFor(class):sub(1, 1)
end

local function Prune()
  local store, now = Store(), JGH.Now()
  if not store then return end
  for id, ev in pairs(store) do
    -- Stubs whose event never arrived go once their sign-ups are old.
    local old = (ev.v or 0) == 0
    for _, s in pairs(ev.signups or {}) do
      if (s.v or 0) + KEEP_DELETED > now then old = false end
    end
    if old or (ev.start and ev.start + KEEP_ARCHIVE < now) or (ev.del and (ev.v or 0) + KEEP_DELETED < now) then
      store[id] = nil
    end
  end
end

-- Heads-ups for anyone signed up at set minutes before the raid; logging in late shows only the latest one passed.
local function Remind()
  local now = JGH.Now()
  for _, ev in ipairs(Raids.List()) do
    local mine = Raids.Mine(ev)
    local left = ev.start - now
    if mine and mine.st ~= "absent" and left > 0 then
      local due = false
      for _, mins in ipairs(REMIND_AT) do
        -- Keyed on the start time too, so a moved raid reminds again.
        local key = ev.id .. ":" .. ev.start .. ":" .. mins
        if left <= mins * 60 and not reminded[key] then
          reminded[key] = true
          due = true
        end
      end
      if due then JGH.Fire("RaidSoon", ev, math.ceil(left / 60)) end
    end
  end
end

function Raids.Init()
  if C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
  JGH.RegisterEvent("CHAT_MSG_ADDON", OnMessage)
  C_Timer.NewTicker(1, Pump)
  C_Timer.NewTicker(15, Remind)
  C_Timer.NewTicker(ASK_EVERY, Raids.Ask)
end

-- Saved raids only become readable once guild info arrives, so the tab refreshes then.
JGH.On("GuildReady", function()
  Prune()
  Changed()
  C_Timer.After(25, Raids.Ask)
end)
