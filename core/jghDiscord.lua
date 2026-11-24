local _, JGH = ...

-- The guild's Discord invite lives in Guild Info, so Blizzard decides who may change it.
local Discord = {}
JGH.Discord = Discord

local LABEL = "Discord: "
local MAX_INFO = 500
-- Lower case; the invite code keeps its own case.
local CORES = { "discord%.gg/[%w%-]+", "discord%.com/invite/[%w%-]+", "discordapp%.com/invite/[%w%-]+" }
local PREFIXES = { "https://www.", "http://www.", "https://", "http://", "www." }

local known
-- Guild Info only reads back the new text once the server confirms it.
local pending, pendingAt, pendingOver

local function InfoText()
  local get = C_GuildInfo and C_GuildInfo.GetInfoText or GetGuildInfoText
  local ok, text = pcall(get)
  if ok and type(text) == "string" and not JGH.IsSecret(text) then
    known = text
    if pending and (text ~= pendingOver or GetTime() - pendingAt > 15) then pending = nil end
  end
  return pending or known
end

-- Start and end of the first invite in text, including any https:// or www. before it.
local function Locate(text)
  local lower = text:lower()
  local s, e
  for _, core in ipairs(CORES) do
    local cs, ce = lower:find(core)
    if cs and (not s or cs < s) then s, e = cs, ce end
  end
  if not s then return nil end
  for _, prefix in ipairs(PREFIXES) do
    if s > #prefix and lower:sub(s - #prefix, s - 1) == prefix then
      s = s - #prefix
      break
    end
  end
  return s, e
end

local function Canonical(link)
  link = link:gsub("^[Hh][Tt][Tt][Pp][Ss]?://", ""):gsub("^[Ww][Ww][Ww]%.", "")
  return "https://" .. link
end

-- Nil when the guild has no invite in its Guild Info.
function Discord.Link()
  local text = InfoText()
  if not text then return nil end
  local s, e = Locate(text)
  return s and Canonical(text:sub(s, e)) or nil
end

-- The invite found in what someone typed, or nil when there is none.
function Discord.Parse(input)
  input = strtrim(input or "")
  local s, e = Locate(input)
  return s and Canonical(input:sub(s, e)) or nil
end

function Discord.CanEdit()
  return IsInGuild() and CanEditGuildInfo ~= nil and CanEditGuildInfo() or false
end

-- Removes the invite, and its whole line when that line only says "Discord:".
local function Without(text, s, e)
  local lineStart = s
  while lineStart > 1 and text:sub(lineStart - 1, lineStart - 1) ~= "\n" do lineStart = lineStart - 1 end
  local lineEnd = text:find("\n", e + 1, true)
  local rest = strtrim(text:sub(lineStart, s - 1) .. text:sub(e + 1, (lineEnd or #text + 1) - 1)):lower()
  if rest ~= "" and rest ~= "discord" and rest ~= "discord:" then
    local left, right = text:sub(1, s - 1), text:sub(e + 1)
    if left:match(" $") and right:match("^ ") then right = right:sub(2) end
    return left .. right
  end
  if lineEnd then return text:sub(1, lineStart - 1) .. text:sub(lineEnd + 1) end
  return (text:sub(1, lineStart - 1):gsub("\n+$", ""))
end

-- Replaces the invite in place, or adds a "Discord:" line. nil removes it. Returns ok, error text.
function Discord.Save(link)
  if not Discord.CanEdit() then return false, "Your rank can't edit Guild Info." end
  local text = InfoText()
  if not text then return false, "Guild Info hasn't loaded yet." end
  local s, e = Locate(text)
  local new
  if link and s then
    new = text:sub(1, s - 1) .. link .. text:sub(e + 1)
  elseif link then
    local body = text:gsub("%s+$", "")
    new = (body == "" and "" or body .. "\n") .. LABEL .. link
  elseif s then
    new = Without(text, s, e)
  else
    return true
  end
  if #new > MAX_INFO then return false, "Guild Info is full. Shorten it first." end
  if not pcall(C_GuildInfo.SetInfoText, new) then return false, "Guild Info can't be changed right now." end
  pending, pendingAt, pendingOver = new, GetTime(), known
  JGH.Fire("DiscordChanged")
  return true
end

-- Guild Info arrives with the roster.
JGH.On("RosterChanged", function() JGH.Fire("DiscordChanged") end)
