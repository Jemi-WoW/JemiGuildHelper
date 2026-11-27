local ADDON, JGH = ...
_G.JemiGuildHelper = JGH

JemiGuildHelperDB = JemiGuildHelperDB or {}

JGH.ADDON = ADDON
JGH.TITLE = "Jemi Guild Helper"
JGH.ICON_TEXTURE = "Interface\\AddOns\\" .. ADDON .. "\\externals\\img\\JemiGuildHelperIcon.tga"
JGH.SYNC_PREFIX = "JemiGuildHelper"

BINDING_HEADER_JEMIGUILDHELPER = "Jemi Guild Helper"
BINDING_NAME_JEMIGUILDHELPER_SCAN = "Fast Invite: scan next"
BINDING_NAME_JEMIGUILDHELPER_POST = "Recruit Message: post to next channel"

local DEFAULTS = {
  hideDays = 3,
  inviteTimeout = 300,
  inviteMode = "copy",
  sync = true,
  mapPins = true,
}

local DEFAULT_MESSAGE = "<%s> is recruiting! Friendly guild for leveling, dungeons and raids. Whisper me for an invite!"
local DEFAULT_TEMPLATE = "Hey {name}! <{guild}> is recruiting, want an invite?"

function JGH.Msg(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cffd4af37[Jemi Guild Helper]|r " .. tostring(text))
end

function JGH.InitDB()
  local db = JemiGuildHelperDB
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then db[k] = v end
  end
  db.minimap = db.minimap or {}
  db.guilds = db.guilds or {}
  db.chars = db.chars or {}
  db.version = 1
end

function JGH.DB()
  return JemiGuildHelperDB
end

function JGH.PlayerName()
  return GetUnitName("player", false) or UnitName("player")
end

function JGH.CharDB()
  local key = UnitGUID("player") or "UNKNOWN"
  local c = JemiGuildHelperDB.chars[key]
  if not c then
    c = { inbox = {} }
    JemiGuildHelperDB.chars[key] = c
  end
  c.name = JGH.PlayerName()
  c.inbox = c.inbox or {}
  return c
end

-- Per-guild data; nil until guild info has arrived.
function JGH.GDB()
  local guild = GetGuildInfo("player")
  if not guild or guild == "" then return nil end
  local g = JemiGuildHelperDB.guilds[guild]
  if not g then
    g = {
      message = DEFAULT_MESSAGE:format(guild),
      template = DEFAULT_TEMPLATE,
      channels = {},
      lastPosted = {},
      contacts = {},
      syncTs = 0,
    }
    JemiGuildHelperDB.guilds[guild] = g
  end
  return g, guild
end

-- Tiny internal message bus between core and UI.
local listeners = {}

function JGH.On(name, fn)
  listeners[name] = listeners[name] or {}
  table.insert(listeners[name], fn)
end

function JGH.Fire(name, ...)
  for _, fn in ipairs(listeners[name] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()(err) end
  end
end

local eventFrame = CreateFrame("Frame")
local handlers = {}

function JGH.RegisterEvent(event, fn)
  if not handlers[event] then
    -- Unknown events error on register, so one missing event cannot break the file.
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return end
    handlers[event] = {}
  end
  table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event]) do
    local ok, err = pcall(fn, event, ...)
    if not ok then geterrorhandler()(err) end
  end
end)

function JGH.TimeAgo(ts)
  if not ts or ts <= 0 then return "never" end
  local d = JGH.Now() - ts
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

-- Fills {name} and {guild} in a template.
function JGH.FillTemplate(template, name)
  local guild = GetGuildInfo("player") or ""
  local out = (template or ""):gsub("{name}", function() return name or "" end)
  out = out:gsub("{guild}", function() return guild end)
  return out
end

-- Chat lines are single-line and pipes must be escaped.
function JGH.CleanChat(text)
  text = (text or ""):gsub("[\r\n]+", " ")
  text = text:gsub("||", "\001"):gsub("|", "||"):gsub("\001", "||")
  return strtrim(text)
end

function JGH.ClassColor(classFile)
  local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  return c
end

function JGH.ColorName(name, classFile)
  local c = JGH.ClassColor(classFile)
  if c then return c:WrapTextInColorCode(name) end
  return name
end
