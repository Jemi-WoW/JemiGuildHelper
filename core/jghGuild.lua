local _, JGH = ...

local roster = {}
local lastAccess

-- Ranks below officer that may still recruit, matched by name in lower case.
JGH.RECRUITER_RANKS = { og = true }

function JGH.IsOfficer()
  if not IsInGuild() then return false end
  if IsGuildLeader() then return true end
  return C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() or false
end

function JGH.IsRecruiter()
  if JGH.IsOfficer() then return true end
  local _, rank = GetGuildInfo("player")
  return type(rank) == "string" and JGH.RECRUITER_RANKS[strtrim(rank):lower()] or false
end

-- The user's own /ginvite fails without the rank's invite right.
function JGH.CanInvite()
  return JGH.IsRecruiter() and (CanGuildInvite == nil or CanGuildInvite()) or false
end

-- Roster names may carry a realm suffix.
local function StripRealm(name)
  return name and (name:gsub("%-[^%s%-]+$", "")) or nil
end
JGH.StripRealm = StripRealm

function JGH.IsGuildMember(name)
  if not name then return false end
  if roster[name] then return true end
  if C_GuildInfo.MemberExistsByName and C_GuildInfo.MemberExistsByName(name) then return true end
  return false
end

local complete = false

-- Legacy roster globals are not in Blizzard's own code on this client.
function JGH.RefreshRoster()
  wipe(roster)
  complete = false
  if not GetNumGuildMembers or not GetGuildRosterInfo then return end
  local total, seen = GetNumGuildMembers() or 0, 0
  for i = 1, total do
    local name, rank, _, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
    if name and not JGH.IsSecret(name) then
      -- Combat can hide these; unknown must not read as offline.
      local known = not JGH.IsSecret(online)
      local info = { classFile = not JGH.IsSecret(classFile) and classFile or nil }
      if known then info.online = online and true or false end
      if not JGH.IsSecret(rank) and type(rank) == "string" then info.rank = rank end
      if not JGH.IsSecret(level) and type(level) == "number" then info.level = level end
      if known and not online and GetGuildRosterLastOnline then
        local y, mo, d, h = GetGuildRosterLastOnline(i)
        if y then info.away = (((y * 365 + mo * 30 + d) * 24) + h) * 3600 end
      end
      roster[name] = info
      roster[StripRealm(name)] = info
      seen = seen + 1
    end
  end
  -- A roster showing online members only must never count as everyone.
  complete = total > 0 and seen == total
end

function JGH.RosterInfo(name)
  return name and roster[name] or nil
end

-- Read only; keyed by name with and without realm.
function JGH.Roster()
  return roster
end

function JGH.RosterComplete()
  return complete
end

function JGH.RequestRoster()
  if IsInGuild() and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end

local function CheckOfficer()
  local now = (JGH.IsOfficer() and "o" or "") .. (JGH.IsRecruiter() and "r" or "")
  if now ~= lastAccess then
    lastAccess = now
    JGH.Fire("OfficerChanged", JGH.IsOfficer())
  end
end
JGH.CheckOfficer = CheckOfficer

JGH.RegisterEvent("GUILD_ROSTER_UPDATE", function()
  JGH.RefreshRoster()
  CheckOfficer()
  JGH.Fire("RosterChanged")
end)

JGH.RegisterEvent("PLAYER_GUILD_UPDATE", function(_, unit)
  if unit and unit ~= "player" then return end
  JGH.RequestRoster()
  CheckOfficer()
end)

JGH.RegisterEvent("GUILD_RANKS_UPDATE", CheckOfficer)
JGH.RegisterEvent("PLAYER_ENTERING_WORLD", CheckOfficer)
