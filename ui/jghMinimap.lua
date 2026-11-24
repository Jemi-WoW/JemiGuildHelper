local _, JGH = ...

local LDB_NAME = "JemiGuildHelper"
local DEFAULT_ANGLE = 210

local ldb, dbicon, dataObject

local function MinimapDB()
  local db = JGH.DB().minimap
  db.minimapPos = tonumber(db.minimapPos) or DEFAULT_ANGLE
  if db.hide == nil then db.hide = false end
  return db
end

local function GetLibs()
  if not LibStub then return end
  ldb = ldb or LibStub:GetLibrary("LibDataBroker-1.1", true)
  dbicon = dbicon or LibStub:GetLibrary("LibDBIcon-1.0", true)
  return ldb, dbicon
end

local function DataObject()
  if dataObject then return dataObject end
  local broker = GetLibs()
  if not broker then return end
  -- NewDataObject returns nil if the name is taken, so reuse that one.
  dataObject = broker:GetDataObjectByName(LDB_NAME) or broker:NewDataObject(LDB_NAME, {
    type = "launcher",
    icon = JGH.ICON_TEXTURE,
    label = JGH.TITLE,
    OnClick = function(_, button)
      if button == "LeftButton" then JGH.TogglePage() elseif button == "RightButton" then JGH.Options.Open() end
    end,
    OnTooltipShow = function(tt)
      if not tt or not tt.AddLine then return end
      tt:AddLine(JGH.TITLE, 1, 0.82, 0)
      tt:AddLine("Left-click: open addon", 1, 1, 1)
      tt:AddLine("Right-click: settings", 1, 1, 1)
      tt:AddLine("Drag: move icon", 1, 1, 1)
      local unread = JGH.IsRecruiter() and JGH.Inbox.Unread() or 0
      if unread > 0 then
        tt:AddLine(("%d unread whisper%s"):format(unread, unread == 1 and "" or "s"), 1, 0.5, 1)
      end
    end,
  })
  return dataObject
end

function JGH.ApplyMinimapButton()
  local obj = DataObject()
  local _, icons = GetLibs()
  if not obj or not icons then return end
  local db = MinimapDB()
  if not icons:IsRegistered(LDB_NAME) then icons:Register(LDB_NAME, obj, db) end
  if db.hide then icons:Hide(LDB_NAME) else icons:Show(LDB_NAME) end
end

function JGH.ToggleMinimapButton()
  local db = MinimapDB()
  db.hide = not db.hide
  JGH.ApplyMinimapButton()
  return not db.hide
end
