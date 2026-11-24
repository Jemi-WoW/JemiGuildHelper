local _, JGH = ...

local Who = {}
JGH.Who = Who

Who.COOLDOWN = 8
local TIMEOUT = 10
local CAP = 50
local RECENT = 20 * 60

Who.queue = {}
Who.results = {}
Who.guilded = {}
Who.stats = { queries = 0, guilded = 0, truncated = 0 }
Who.state = "idle"
Who.lastSend = 0
Who.lastQuery = nil
Who.params = nil
Who.skip = {}
-- Answers by query text, kept across scans: { at, num, total, found }.
Who.searched = {}

local pending, Split

local function QueryText(q)
  local parts = {}
  if q.race then parts[#parts + 1] = ('r-"%s"'):format(q.race) end
  if q.class then parts[#parts + 1] = ('c-"%s"'):format(q.class) end
  parts[#parts + 1] = q.min .. "-" .. q.max
  return table.concat(parts, " ")
end
Who.QueryText = QueryText

function Who.Describe(q)
  if not q then return "" end
  local text = q.min == q.max and ("Level " .. q.min) or ("Level " .. q.min .. "-" .. q.max)
  if q.class then text = text .. " " .. q.class end
  if q.race then text = text .. " " .. q.race end
  return text
end

function Who.Reset()
  wipe(Who.queue)
  wipe(Who.results)
  wipe(Who.guilded)
  Who.stats.queries, Who.stats.guilded, Who.stats.truncated = 0, 0, 0
  Who.state = "idle"
  Who.lastQuery = nil
  Who.params = nil
  wipe(Who.skip)
  JGH.Fire("WhoChanged")
end

-- Levels per starting search; a wide search keeps hitting the same first 50 the server finds.
local SEED_SPAN = 5

local function Shuffle(t)
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

-- Seeds a fresh scan; classNames are localized, empty for all classes; skipFiles are class files left out.
function Who.Start(minLevel, maxLevel, classNames, skipFiles)
  Who.Reset()
  classNames, skipFiles = classNames or {}, skipFiles or {}
  for _, file in ipairs(skipFiles) do Who.skip[file] = true end
  Who.params = { min = minLevel, max = maxLevel, classes = table.concat(classNames, ","), skip = table.concat(skipFiles, ",") }
  local classes = #classNames > 0 and classNames or { false }
  for lo = minLevel, maxLevel, SEED_SPAN do
    local hi = math.min(maxLevel, lo + SEED_SPAN - 1)
    for _, name in ipairs(classes) do
      Who.queue[#Who.queue + 1] = { min = lo, max = hi, class = name or nil }
    end
  end
  -- Random order, so each new scan starts on different players.
  Shuffle(Who.queue)
  Who.state = "ready"
  JGH.Fire("WhoChanged")
end

function Who.ReadyIn()
  return math.max(0, Who.lastSend + Who.COOLDOWN - GetTime())
end

function Who.Remaining()
  return #Who.queue
end

local function Restore()
  if LFGWhoListFrame then LFGWhoListFrame:RegisterEvent("WHO_LIST_UPDATE") end
  if not (LFGWhoListFrame and LFGWhoListFrame:IsShown()) then C_FriendList.SetWhoToUi(false) end
  pending = nil
end

local function Capped(num, total)
  -- Forever reports the total as the capped count, so a full page means more exist.
  return num >= CAP - 1 or total > num
end

-- A search answered a moment ago is reused, so a new scan goes deeper instead of seeing the same players again.
local function TakeNext()
  local q = table.remove(Who.queue, 1)
  while q do
    local seen = Who.searched[QueryText(q)]
    if not seen or GetTime() - seen.at > RECENT then return q end
    for _, r in ipairs(seen.found) do
      if not JGH.IsGuildMember(r.name) and not Who.skip[r.classFile or ""] then Who.results[r.name] = r end
    end
    if Capped(seen.num, seen.total) then Split(q, seen.num, seen.total) end
    q = table.remove(Who.queue, 1)
  end
end

-- Must run inside a click or key press.
function Who.Next()
  if pending then return false, "Waiting for the last /who" end
  if JGH.WhoDisabled() then return false, "/who is disabled here" end
  if Who.ReadyIn() > 0 then return false, "Cooldown" end
  local had = #Who.queue > 0
  local q = TakeNext()
  if not q then
    Who.state = "done"
    JGH.Fire("WhoChanged")
    return false, had and "All of this was searched in the last 20 minutes" or "Nothing queued"
  end

  -- Forever's Group Finder pops open on every who result unless muted.
  if LFGWhoListFrame and not LFGWhoListFrame:IsShown() then
    LFGWhoListFrame:UnregisterEvent("WHO_LIST_UPDATE")
  end
  C_FriendList.SetWhoToUi(true)
  pending = q
  Who.lastQuery = q
  Who.lastSend = GetTime()
  Who.state = "waiting"
  C_FriendList.SendWho(QueryText(q), Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social or nil)
  JGH.Fire("WhoChanged")

  -- Throttled queries are dropped silently, so retry the same bucket.
  C_Timer.After(TIMEOUT, function()
    if pending == q then
      Restore()
      table.insert(Who.queue, 1, q)
      Who.state = "ready"
      Who.timedOut = true
      JGH.Fire("WhoChanged")
    end
  end)
  return true
end

local DEFAULT_SPLIT = 4

function Split(q, num, total)
  local children = {}
  if q.max > q.min then
    local span = q.max - q.min + 1
    local k = total > num and math.ceil(total / 45) or DEFAULT_SPLIT
    k = math.min(span, math.max(2, k))
    local start = q.min
    for i = 1, k do
      local stop = (i == k) and q.max or (q.min + math.floor(span * i / k) - 1)
      if stop >= start then
        children[#children + 1] = { min = start, max = stop, class = q.class, race = q.race }
        start = stop + 1
      end
    end
  elseif not q.class then
    for _, c in ipairs(JGH.ClassList()) do
      if not Who.skip[c.file] then children[#children + 1] = { min = q.min, max = q.max, class = c.name } end
    end
  elseif not q.race then
    for _, race in ipairs(JGH.RaceList()) do
      children[#children + 1] = { min = q.min, max = q.max, class = q.class, race = race }
    end
  end
  -- Narrower searches wait at the back, so every level and class gets a first look before any is split further.
  for _, child in ipairs(Shuffle(children)) do Who.queue[#Who.queue + 1] = child end
  return #children > 0
end

local function Collect()
  local me = JGH.PlayerName()
  local num, total = C_FriendList.GetNumWhoResults()
  num, total = num or 0, total or 0
  local found = {}
  for i = 1, num do
    local w = C_FriendList.GetWhoInfo(i)
    local name = w and w.fullName
    if name and not JGH.IsSecret(name) and name ~= me and not Who.skip[w.filename or ""] then
      if (w.fullGuildName and w.fullGuildName ~= "") or JGH.IsGuildMember(name) then
        if not Who.guilded[name] then
          Who.guilded[name] = true
          Who.stats.guilded = Who.stats.guilded + 1
        end
        Who.results[name] = nil
      else
        local r = {
          name = name,
          level = w.level or 0,
          class = w.classStr or "",
          classFile = w.filename,
          race = w.raceStr or "",
          zone = w.area or "",
          seen = JGH.Now(),
        }
        Who.results[name] = r
        found[#found + 1] = r
      end
    end
  end
  return num, total, found
end

JGH.RegisterEvent("WHO_LIST_UPDATE", function()
  if not pending then return end
  local q = pending
  Restore()
  Who.timedOut = nil
  Who.stats.queries = Who.stats.queries + 1
  local num, total, found = Collect()
  Who.searched[QueryText(q)] = { at = GetTime(), num = num, total = total, found = found }
  if Capped(num, total) then
    if not Split(q, num, total) then
      Who.stats.truncated = Who.stats.truncated + 1
    end
  end
  Who.state = #Who.queue > 0 and "ready" or "done"
  JGH.Fire("WhoChanged")
end)

-- Players who joined since the scan drop out.
JGH.On("RosterChanged", function()
  local removed = false
  for name in pairs(Who.results) do
    if JGH.IsGuildMember(name) then
      Who.results[name] = nil
      removed = true
    end
  end
  if removed then JGH.Fire("WhoChanged") end
end)
