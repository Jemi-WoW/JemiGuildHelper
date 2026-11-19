local _, ZR = ...

local UI = {}
ZR.UI = UI

local GOLD = { 1, 0.82, 0 }
UI.GOLD = GOLD

-- Spellbook-style square icon tab, without TabSystemButtonMixin (it taints an upvalue).
function UI.CreateIconTab(parent, icon, tooltip)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(44, 32)
  b:SetMotionScriptsWhileDisabled(true)
  b.Icon = b:CreateTexture(nil, "ARTWORK")
  b.Icon:SetSize(36, 35)
  b.Icon:SetPoint("CENTER")
  b.Icon:SetTexture(icon)
  local mask = b:CreateMaskTexture()
  mask:SetAtlas("SquareMask")
  mask:SetPoint("TOPLEFT", b.Icon, "TOPLEFT", 0, -2)
  mask:SetPoint("BOTTOMRIGHT", b.Icon, "BOTTOMRIGHT", -2, 0)
  b.Icon:AddMaskTexture(mask)
  b.Frame = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.Frame:SetAtlas("spellbook-Tab-Frame-C60", true)
  b.Frame:SetPoint("BOTTOM", 0, 1)
  b.Active = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.Active:SetAtlas("spellbook-Tab-Frame-Glow-C60", true)
  b.Active:SetPoint("BOTTOM", 0, 1)
  b.Glow = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.Glow:SetAtlas("spellbook-Tab-Frame-glow-gradient-C60", true)
  b.Glow:SetPoint("BOTTOM")
  b.tooltipText = tooltip
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -12, -6)
    GameTooltip_AddNormalLine(GameTooltip, self.tooltipText)
    if self.tooltipNote then GameTooltip_AddErrorLine(GameTooltip, self.tooltipNote) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  UI.SetIconTabSelected(b, false)
  return b
end

function UI.SetIconTabSelected(b, selected)
  b.Frame:SetShown(not selected)
  b.Active:SetShown(selected)
  b.Glow:SetShown(selected)
  b:SetEnabled(not selected)
end

function UI.Text(parent, font, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
  if text then fs:SetText(text) end
  return fs
end

-- Gold label above a dark tooltip-bordered box, like the chat settings boxes.
function UI.CreateBox(parent, title)
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  box:SetBackdropColor(0, 0, 0, 0.55)
  box:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
  if title then
    box.Title = UI.Text(box, "GameFontNormal", title)
    box.Title:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 4, 2)
  end
  return box
end

function UI.CreateButton(parent, text, width, height)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 130, height or 20)
  b:SetText(text or "")
  b:SetMotionScriptsWhileDisabled(true)
  return b
end

-- Shows a tooltip even while the button is disabled.
function UI.SetButtonTooltip(b, getText)
  b:SetScript("OnEnter", function(self)
    local title, note = getText(self)
    if not title then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, title)
    if note then GameTooltip_AddNormalLine(GameTooltip, note) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
end

function UI.CreateInput(parent, width, height)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width or 120, height or 22)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEnterPressed", e.ClearFocus)
  return e
end

function UI.CreateCheck(parent, text)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  if c.Text then
    c.Text:SetFontObject("GameFontHighlightSmall")
    c.Text:SetText(text or "")
  end
  return c
end

function UI.ClassIcon(classFile, size)
  if not classFile then return "" end
  return CreateAtlasMarkup("classicon-" .. classFile:lower(), size or 14, size or 14)
end

-- Guild-frame header bar, as on the Guild Info page.
function UI.CreateHeaderBar(parent, text, width)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetSize(width or 280, 22)
  local tex = bar:CreateTexture(nil, "BACKGROUND")
  tex:SetTexture("Interface\\GuildFrame\\GuildFrame")
  tex:SetTexCoord(0.00097656, 0.31445313, 0.93164063, 0.97460938)
  tex:SetAllPoints()
  bar.Text = UI.Text(bar, "GameFontNormal", text)
  bar.Text:SetPoint("LEFT", 10, 0)
  return bar
end

-- Roster-style list: column headers over a ScrollBox with a minimal bar.
function UI.CreateTable(parent, columns, extraColumn, rowHeight, initRow)
  local t = CreateFrame("Frame", nil, parent)

  t.Header = CreateFrame("Frame", nil, t, "ColumnDisplayTemplate")
  t.Header:SetPoint("TOPLEFT", -2, 0)
  t.Header:SetPoint("TOPRIGHT", 0, 0)
  t.Header:SetHeight(22)
  if t.Header.Background then t.Header.Background:Hide() end
  if t.Header.TopTileStreaks then t.Header.TopTileStreaks:Hide() end
  t.Header:LayoutColumns(columns, extraColumn)

  t.ScrollBox = CreateFrame("Frame", nil, t, "WowScrollBoxList")
  t.ScrollBox:SetPoint("TOPLEFT", 0, -24)
  t.ScrollBox:SetPoint("BOTTOMRIGHT", -18, 0)

  t.ScrollBar = CreateFrame("EventFrame", nil, t, "MinimalScrollBar")
  t.ScrollBar:SetPoint("TOPLEFT", t.ScrollBox, "TOPRIGHT", 6, -2)
  t.ScrollBar:SetPoint("BOTTOMLEFT", t.ScrollBox, "BOTTOMRIGHT", 6, 2)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(rowHeight or 20)
  view:SetElementInitializer("Button", initRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(t.ScrollBox, t.ScrollBar, view)

  function t:SetRows(rows)
    self.ScrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
  end

  function t:Refresh()
    self.ScrollBox:ForEachFrame(function(row)
      local data = row.GetElementData and row:GetElementData()
      if data then initRow(row, data) end
    end)
  end

  return t
end

-- Native roster row art and highlight.
function UI.StyleRow(row)
  row:SetNormalTexture("Interface\\GuildFrame\\GuildFrame")
  row:GetNormalTexture():SetTexCoord(0.36230469, 0.38183594, 0.95898438, 0.99804688)
  row:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar", "ADD")
end

function UI.CreateCell(row, font, justify)
  local fs = row:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

function UI.Whisper(name)
  local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
  if tell then tell(name) end
end

function UI.InviteToGroup(name)
  local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
  if invite then invite(name) end
end

-- Right-click actions for a guild member, the same everywhere.
function UI.NameMenu(owner, name, classFile, fromMap)
  if not MenuUtil or not MenuUtil.CreateContextMenu then return end
  local other = name ~= ZR.PlayerName()
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(ZR.ColorName(name, classFile))
    root:CreateButton(WHISPER or "Whisper", function() UI.Whisper(name) end):SetEnabled(other)
    root:CreateButton("Invite to group", function() UI.InviteToGroup(name) end):SetEnabled(other)
    if not fromMap and UI.ShowOnMap then
      root:CreateButton("Show on map", function() UI.ShowOnMap(name) end):SetEnabled(ZR.Map.Get(name) ~= nil)
    end
    root:CreateButton("Copy name", function()
      ZR.ShowCopyBox("Copy name", "Press Ctrl+C to copy it.", name)
    end)
  end)
end

local picker

-- first maps names listed ahead of everyone (a raid's sign-ups) to their class, so guests show too.
local function Members(filter, first)
  local out, seen, listed = {}, {}, {}
  for name, info in pairs(ZR.Roster()) do
    if not name:find("-", 1, true) and not seen[info] and (filter == "" or name:lower():find(filter, 1, true)) then
      seen[info] = true
      listed[name] = true
      out[#out + 1] = { name = name, info = info, first = first and first[name] and true or false }
    end
  end
  for name, class in pairs(first or {}) do
    if not listed[name] and not ZR.RosterInfo(name) and (filter == "" or name:lower():find(filter, 1, true)) then
      out[#out + 1] = { name = name, info = { classFile = class ~= true and class or nil }, first = true }
    end
  end
  table.sort(out, function(a, b)
    if a.first ~= b.first then return a.first end
    local ao, bo = a.info.online and true or false, b.info.online and true or false
    if ao ~= bo then return ao end
    return a.name < b.name
  end)
  return out
end

local function Pick(name, guest)
  local owner, onPick = picker.owner, picker.onPick
  picker:Hide()
  if not owner or not name or name == "" then return end
  if owner.SetMember then owner:SetMember(name) end
  if onPick then onPick(name, guest) end
end

-- Typed names get capitals like in-game names.
local function NameCase(text)
  return (strtrim(text):gsub("%s+", " "):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b:lower() end))
end

local function PickerRow(row, data)
  if not row.Name then
    row:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar", "ADD")
    row.Dot = row:CreateTexture(nil, "ARTWORK")
    row.Dot:SetSize(12, 12)
    row.Dot:SetPoint("LEFT", 4, 0)
    row.Class = row:CreateTexture(nil, "ARTWORK")
    row.Class:SetSize(14, 14)
    row.Class:SetPoint("LEFT", row.Dot, "RIGHT", 4, 0)
    row.Level = UI.CreateCell(row, "GameFontDisableSmall", "RIGHT")
    row.Level:SetPoint("RIGHT", -6, 0)
    row.Name = UI.CreateCell(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", row.Class, "RIGHT", 5, 0)
    row.Name:SetPoint("RIGHT", row.Level, "LEFT", -4, 0)
    row:SetScript("OnClick", function(self) Pick(self.name, self.guest) end)
  end
  local info = data.info
  row.name, row.guest = data.name, data.guest
  if data.guest then
    row.Dot:Hide()
    row.Class:Hide()
    row.Name:SetText(("|cff40ff40+ Add \"%s\" as a guest|r"):format(data.name))
    row.Level:SetText("")
    return
  end
  row.Dot:Show()
  row.Dot:SetTexture(info.online and "Interface\\FriendsFrame\\StatusIcon-Online" or "Interface\\FriendsFrame\\StatusIcon-Offline")
  row.Class:SetShown(info.classFile ~= nil)
  if info.classFile then row.Class:SetAtlas("classicon-" .. info.classFile:lower()) end
  row.Name:SetText(ZR.ColorName(data.name, info.classFile))
  row.Level:SetText(data.first and "|cff40ff40signed|r" or (info.level or ""))
end

local function Refresh()
  local text = strtrim(picker.Search:GetText())
  local list = Members(text:lower(), picker.first)
  -- Someone outside the guild can be added by name.
  if picker.allowGuest and text ~= "" then
    local exact = false
    for _, m in ipairs(list) do
      if m.name:lower() == text:lower() then exact = true end
    end
    if not exact then table.insert(list, 1, { name = NameCase(text), info = {}, guest = true }) end
  end
  picker.List:SetRows(list)
  picker.Empty:SetShown(#list == 0)
  picker.top = list[1] and list[1].name
  picker.topGuest = list[1] and list[1].guest
end

local function BuildPicker()
  picker = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  picker:SetSize(240, 280)
  picker:SetFrameStrata("FULLSCREEN_DIALOG")
  picker:SetClampedToScreen(true)
  picker:EnableMouse(true)
  picker:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  picker:SetBackdropColor(0.05, 0.05, 0.05, 1)
  picker:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  picker.Search = CreateFrame("EditBox", nil, picker, "SearchBoxTemplate")
  picker.Search:SetHeight(20)
  picker.Search:SetPoint("TOPLEFT", 14, -8)
  picker.Search:SetPoint("TOPRIGHT", -10, -8)
  picker.Search:HookScript("OnTextChanged", Refresh)
  picker.Search:SetScript("OnEscapePressed", function() picker:Hide() end)
  -- Enter takes the top match, or the typed name when nobody matches.
  picker.Search:SetScript("OnEnterPressed", function(self)
    if picker.top then Pick(picker.top, picker.topGuest) else Pick(strtrim(self:GetText())) end
  end)
  picker.List = UI.CreateTable(picker, { { title = "", width = 0 } }, nil, 20, PickerRow)
  picker.List:SetPoint("TOPLEFT", 8, -34)
  picker.List:SetPoint("BOTTOMRIGHT", -8, 8)
  picker.List.Header:Hide()
  picker.List.ScrollBox:SetPoint("TOPLEFT", picker.List, "TOPLEFT", 0, 0)
  picker.Empty = UI.Text(picker, "GameFontDisableSmall", "No guild member by that name.")
  picker.Empty:SetPoint("CENTER", 0, -10)
  -- Closes on a click anywhere else, like a normal dropdown.
  picker:SetScript("OnUpdate", function(self)
    local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
    if down and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
  end)
  picker:SetScript("OnHide", function(self)
    self.Search:ClearFocus()
    self.owner, self.onPick, self.first, self.allowGuest = nil, nil, nil, nil
  end)
  picker:Hide()
end

local function TogglePicker(owner, onPick, first, allowGuest)
  if not picker then BuildPicker() end
  if picker:IsShown() and picker.owner == owner then
    picker:Hide()
    return
  end
  ZR.RequestRoster()
  picker.owner, picker.onPick, picker.first, picker.allowGuest = owner, onPick, first, allowGuest
  picker:ClearAllPoints()
  picker:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  picker.Search:SetText("")
  picker:Show()
  Refresh()
  picker.Search:SetFocus()
end

-- A dropdown of guild members with a search box; onPick(name) runs after a choice.
function UI.CreateMemberPicker(parent, width, onPick)
  local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  dd:SetWidth(width)
  dd.onPick = onPick
  function dd:SetMember(name)
    self.member = name
    local info = ZR.RosterInfo(name)
    local text = ZR.ColorName(name, info and info.classFile)
    if self.SetDefaultText then self:SetDefaultText(text) elseif self.Text then self.Text:SetText(text) end
  end
  function dd:GetMember()
    return self.member
  end
  dd:HookScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then TogglePicker(self, self.onPick) end
  end)
  dd:HookScript("OnHide", function(self)
    if picker and picker.owner == self then picker:Hide() end
  end)
  return dd
end

-- Opens the member list under anchor; onPick(name, guest). allowGuest offers typed names from outside the guild.
function UI.PickMember(anchor, onPick, first, allowGuest)
  TogglePicker(anchor, onPick, first, allowGuest)
end
