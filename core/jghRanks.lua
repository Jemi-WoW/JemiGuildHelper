local _, JGH = ...

-- Which guild ranks may use Recruitment. The Guild Master picks them in Guild Settings.
local Ranks = {}
JGH.Ranks = Ranks

local PREFIX = "JGHRanks"
local PROTO = "1"
-- One character per rank from the top; "1" can recruit.
local DEFAULT = "11"
local MAX_RANKS = 10

local pending
local announceTimer

local function Config()
  local g = JGH.GDB()
  return g and g.rankAccess
end

local function Bits()
  local c = Config()
  return c and c.bits or DEFAULT
end

function Ranks.Version()
  local c = Config()
  return c and c.v or 0
end

function Ranks.IsDefault()
  return Bits() == DEFAULT
end

function Ranks.Count()
  local n = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
  return math.min(n, MAX_RANKS)
end

local function RawName(order)
  local name = GuildControlGetRankName and GuildControlGetRankName(order)
  if type(name) ~= "string" or JGH.IsSecret(name) or name == "" then return nil end
  return name
end

function Ranks.Name(order)
  return RawName(order) or (RANK or "Rank") .. " " .. order
end

-- order counts from 1, the Guild Master.
function Ranks.CanRecruit(order)
  return order == 1 or Bits():sub(order, order) == "1"
end

function Ranks.MyOrder()
  local _, _, index = GetGuildInfo("player")
  if JGH.IsSecret(index) or type(index) ~= "number" then return nil end
  return index + 1
end

function Ranks.AllowedNames()
  local out = {}
  for i = 1, Ranks.Count() do
    if Ranks.CanRecruit(i) then out[#out + 1] = Ranks.Name(i) end
  end
  return out
end

-- Nil while any rank name has not arrived yet.
local function RankNames()
  local out = {}
  for i = 1, Ranks.Count() do
    out[i] = RawName(i)
    if not out[i] then return nil end
  end
  return #out > 0 and out or nil
end

local function Send(msg)
  pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
end

local function Announce(delay)
  if not IsGuildLeader() or Ranks.Version() == 0 then return end
  if announceTimer then announceTimer:Cancel() end
  announceTimer = C_Timer.NewTimer(delay, function()
    announceTimer = nil
    if IsGuildLeader() and Ranks.Version() > 0 then
      Send(table.concat({ PROTO, "R", Ranks.Version(), Bits() }, "|"))
    end
  end)
end

local function Ask()
  if IsInGuild() and not IsGuildLeader() then
    Send(table.concat({ PROTO, "Q", Ranks.Version() }, "|"))
  end
end

local function Changed()
  JGH.CheckOfficer()
  JGH.Fire("RankAccessChanged")
end

local function Save(bits)
  local g = JGH.GDB()
  if not g then return end
  bits = "1" .. (bits:sub(2):gsub("0+$", ""))
  g.rankAccess = { v = math.max(JGH.Now(), Ranks.Version() + 1), bits = bits, names = RankNames() }
  Changed()
  Announce(2)
end

function Ranks.Set(order, on)
  if not IsGuildLeader() or order < 2 or order > MAX_RANKS then return end
  local bits = Bits()
  if #bits < order then bits = bits .. ("0"):rep(order - #bits) end
  Save(bits:sub(1, order - 1) .. (on and "1" or "0") .. bits:sub(order + 1))
end

function Ranks.Reset()
  if IsGuildLeader() then Save(DEFAULT) end
end

-- Settings stay with their rank when the Guild Master renames, moves, adds or deletes ranks.
local function Reconcile()
  local c = Config()
  if not c or not IsGuildLeader() then return end
  local now = RankNames()
  if not now then return end
  if not c.names then
    c.names = now
    return
  end
  if table.concat(now, "\001") == table.concat(c.names, "\001") then return end
  local present, used, bits = {}, {}, {}
  for _, name in ipairs(now) do present[name] = true end
  for i, name in ipairs(now) do
    local from
    for j, old in ipairs(c.names) do
      if old == name and not used[j] then
        from = j
        break
      end
    end
    -- No name match and the old name is gone: renamed in place.
    if not from and c.names[i] and not present[c.names[i]] and not used[i] then from = i end
    if from then used[from] = true end
    bits[i] = from and c.bits:sub(from, from) == "1" and "1" or "0"
  end
  Save(table.concat(bits))
end

local function IsLeader(name)
  local info = JGH.RosterInfo(name)
  if not info or info.rankIndex == nil then return nil end
  return info.rankIndex == 0
end

-- Only taken straight from the Guild Master, so nobody else can change who recruits.
local function TryPending()
  local g = JGH.GDB()
  if not pending or not g then return end
  local leader = IsLeader(pending.from)
  if leader == nil then return end
  local p = pending
  pending = nil
  if not leader or p.v <= Ranks.Version() then return end
  g.rankAccess = { v = p.v, bits = p.bits }
  Changed()
end

local function OnMessage(_, prefix, text, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" then return end
  if JGH.IsSecret(text) or JGH.IsSecret(sender) then return end
  sender = JGH.StripRealm(sender)
  if sender == JGH.PlayerName() then return end
  local f = { strsplit("|", text) }
  if f[1] ~= PROTO then return end
  if f[2] == "Q" then
    if (tonumber(f[3]) or 0) < Ranks.Version() then Announce(1 + math.random() * 2) end
  elseif f[2] == "R" then
    local v, bits = tonumber(f[3]), f[4]
    if v and bits and #bits <= MAX_RANKS and bits:match("^1[01]*$") then
      pending = { v = v, bits = bits, from = sender }
      TryPending()
    end
  end
end

function Ranks.Init()
  if C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
  JGH.RegisterEvent("CHAT_MSG_ADDON", OnMessage)
  JGH.RegisterEvent("GUILD_RANKS_UPDATE", function()
    Reconcile()
    JGH.Fire("RankAccessChanged")
  end)
end

JGH.On("RosterChanged", TryPending)

-- Saved settings only become readable once guild info arrives.
JGH.On("GuildReady", function()
  Changed()
  C_Timer.After(8 + math.random() * 4, Ask)
  Announce(10)
end)
