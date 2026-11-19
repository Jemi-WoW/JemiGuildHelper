local _, ZR = ...
local UI = ZR.UI
local Raids = ZR.Raids

local LIST_WIDTH = 210
local ENTRY_HEIGHT = 16
local HEADER_HEIGHT = 22
local GAP = 6
local BUTTON_WIDTH = 74
local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local WAITING = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local LATE = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local BENCH = "Interface\\Icons\\INV_Misc_Note_02"
local MINE_ICONS = { ["in"] = READY, late = LATE, tent = WAITING, bench = BENCH, absent = NOT_READY }
local SECTIONS = {
  { st = "tent", title = "Tentative", icon = WAITING },
  { st = "bench", title = "Bench", icon = BENCH },
  { st = "absent", title = "Absent", icon = NOT_READY },
}
local LOOT_ICON = "Interface\\Icons\\INV_Misc_Bag_07"
local KIND_TAGS = { H = "|cffff8040HR|r", S = "|cff40ff40SR|r" }
local KIND_NAMES = { H = "Hard reserve", S = "Soft reserve" }

local view
local selected
local armed
local archive

local function Selected()
  return selected and Raids.Get(selected)
end

local function When(ts)
  return Raids.When(ts)
end

-- Sets a waypoint on the entrance and opens the map there.
function UI.ShowRaidLocation(info)
  if not info or not info.map then return end
  if C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(info.map) and UiMapPoint then
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(info.map, info.x, info.y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  end
  if WorldMapFrame:IsShown() then
    WorldMapFrame:SetMapID(info.map)
  elseif InCombatLockdown() then
    ZR.Msg("Waypoint set; open your map to see it.")
  else
    OpenWorldMap(info.map)
  end
end

-- getInfo returns the raid whose entrance it shows, read on each click.
function UI.CreateRaidMapButton(parent, getInfo)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(22, 22)
  b:SetNormalTexture("Interface\\Icons\\INV_Misc_Map_01")
  b:GetNormalTexture():SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetPushedTexture("Interface\\Icons\\INV_Misc_Map_01")
  b:GetPushedTexture():SetTexCoord(0.1, 0.9, 0.1, 0.9)
  b:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    UI.ShowRaidLocation(getInfo())
  end)
  b:SetScript("OnEnter", function(self)
    local info = getInfo()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, "Show on map")
    if info and info.where then GameTooltip:AddLine(info.name .. " is in " .. info.where .. ".", 1, 1, 1) end
    GameTooltip:AddLine("Opens the map with a waypoint on the entrance.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function Countdown(ts)
  local d = ts - ZR.Now()
  if d <= 0 then return d > -3 * 3600 and "started" or ("started " .. ZR.TimeAgo(ts)) end
  if d < 3600 then return ("in %dm"):format(math.ceil(d / 60)) end
  if d < 86400 then return ("in %dh %dm"):format(math.floor(d / 3600), math.floor(d % 3600 / 60)) end
  return ("in %dd %dh"):format(math.floor(d / 86400), math.floor(d % 86400 / 3600))
end

local WRAP = 60

-- Tooltip lines of at most WRAP characters; overlong words are cut so nothing runs off.
local function WrapLines(text)
  local out = {}
  for para in (text .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      while #word > WRAP do
        if line ~= "" then
          out[#out + 1] = line
          line = ""
        end
        local cut = WRAP
        -- Never split inside a multi-byte letter.
        while cut > 1 and word:byte(cut + 1) and word:byte(cut + 1) >= 128 and word:byte(cut + 1) < 192 do cut = cut - 1 end
        out[#out + 1] = word:sub(1, cut)
        word = word:sub(cut + 1)
      end
      if line == "" then
        line = word
      elseif #line + 1 + #word <= WRAP then
        line = line .. " " .. word
      else
        out[#out + 1] = line
        line = word
      end
    end
    out[#out + 1] = line
  end
  return out
end

local function ClassName(file)
  local c = file and ZR.ClassByFile(file)
  return c and c.name or ""
end

local function Icon(path, size)
  return ("|T%s:%d:%d|t"):format(path, size or 14, size or 14)
end

-- List ------------------------------------------------------------------

local function Select(id)
  selected = id
  ZR.DB().raidSelected = id
  view.Editor:Hide()
  view.Update()
end

local function InitRow(row, data)
  if not row.Title then
    UI.StyleRow(row)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(30, 30)
    row.Icon:SetPoint("LEFT", 6, 0)
    row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.Title = UI.CreateCell(row, "GameFontNormal")
    row.Title:SetPoint("TOPLEFT", 44, -6)
    row.Title:SetPoint("TOPRIGHT", -46, -6)
    row.When = UI.CreateCell(row, "GameFontHighlightSmall")
    row.When:SetPoint("BOTTOMLEFT", 44, 7)
    row.When:SetPoint("BOTTOMRIGHT", -26, 7)
    row.Count = UI.CreateCell(row, "GameFontHighlightSmall", "RIGHT")
    row.Count:SetPoint("TOPRIGHT", -8, -7)
    row.Mine = row:CreateTexture(nil, "ARTWORK")
    row.Mine:SetSize(14, 14)
    row.Mine:SetPoint("BOTTOMRIGHT", -8, 6)
    row.Selected = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.Selected:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar")
    row.Selected:SetBlendMode("ADD")
    row.Selected:SetAllPoints()
    row:SetScript("OnClick", function(self)
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
      Select(self.ev.id)
    end)
  end
  local ev = data.ev
  row.ev = ev
  row.Icon:SetTexture(Raids.Info(ev.raid).icon)
  row.Title:SetText(Raids.Title(ev))
  local started = ev.start <= ZR.Now()
  row.When:SetText(started and ("|cff888888" .. When(ev.start) .. "|r") or When(ev.start))
  local c = Raids.Counts(ev)
  row.Count:SetText(("%d/%d"):format(c.going, ev.size or 0))
  local mine = Raids.Mine(ev)
  row.Mine:SetShown(mine ~= nil)
  if mine then row.Mine:SetTexture(MINE_ICONS[mine.st] or READY) end
  row.Selected:SetShown(ev.id == selected)
end

-- Roster ----------------------------------------------------------------

local function EntryTooltip(e)
  local d = e.data
  GameTooltip:SetOwner(e, "ANCHOR_RIGHT")
  GameTooltip_SetTitle(GameTooltip, ZR.ColorName(d.name, d.s.c))
  local role = Raids.ROLE_NAMES[d.s.role or ""]
  GameTooltip:AddLine(table.concat({ role or "", ClassName(d.s.c) }, " "), 1, 1, 1)
  GameTooltip:AddLine(Raids.STATUS_NAMES[d.s.st] or "", 1, 0.82, 0)
  if d.s.g then GameTooltip:AddLine("Guest, not in the guild", 0.6, 0.6, 0.6) end
  if d.s.note and d.s.note ~= "" then GameTooltip:AddLine("\"" .. d.s.note .. "\"", 0.9, 0.9, 0.9, true) end
  if (d.s.at or 0) > 0 then GameTooltip:AddLine("Signed up " .. When(d.s.at), 0.5, 0.5, 0.5) end
  local ev = Selected()
  for _, r in ipairs(ev and Raids.Reserves(ev, d.name) or {}) do
    GameTooltip:AddLine(("%s: |c%s%s|r"):format(KIND_NAMES[r.k], Raids.ItemColor(r.i), Raids.ItemName(r.i)), 1, 0.82, 0)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(ZR.IsOfficer() and "Right-click to move or remove them." or "Right-click for more.", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function EntryMenu(e)
  local d, ev = e.data, Selected()
  if not ev then return end
  if not ZR.IsOfficer() then return UI.NameMenu(e, d.name, d.s.c) end
  MenuUtil.CreateContextMenu(e, function(_, root)
    root:CreateTitle(ZR.ColorName(d.name, d.s.c))
    local other = d.name ~= ZR.PlayerName()
    root:CreateButton(WHISPER or "Whisper", function() UI.Whisper(d.name) end):SetEnabled(other)
    root:CreateButton("Invite to group", function() UI.InviteToGroup(d.name) end):SetEnabled(other)
    local move = root:CreateButton("Move to")
    for _, role in ipairs(Raids.ROLES) do
      if Raids.CanRole(d.s.c, role) then
        move:CreateButton(Icon(Raids.ROLE_ICONS[role]) .. " " .. Raids.ROLE_NAMES[role], function()
          Raids.SetSignup(ev.id, d.name, d.s.st == "late" and "late" or "in", role)
        end)
      end
    end
    for _, sec in ipairs(SECTIONS) do
      move:CreateButton(Icon(sec.icon) .. " " .. sec.title, function() Raids.SetSignup(ev.id, d.name, sec.st) end)
    end
    root:CreateButton("Remove sign-up", function() Raids.SetSignup(ev.id, d.name, "x") end)
  end)
end

local function LootTooltip(row)
  local r = row.data
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  Raids.ShowItemTooltip(GameTooltip, r.i)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(("%s for %s"):format(KIND_NAMES[r.k], r.n), 1, 0.82, 0)
  GameTooltip:AddLine(("Drops from %s"):format(r.b), 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

local function LootRow(col, i)
  col.rows = col.rows or {}
  local row = col.rows[i]
  if not row then
    row = CreateFrame("Button", nil, col)
    row:SetHeight(ENTRY_HEIGHT)
    row:SetPoint("TOPLEFT", col, "TOPLEFT", 2, -HEADER_HEIGHT - 2 - (i - 1) * ENTRY_HEIGHT)
    row:SetPoint("RIGHT", col, "RIGHT", -2, 0)
    row:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar", "ADD")
    row.Tag = UI.CreateCell(row, "GameFontNormalSmall")
    row.Tag:SetPoint("LEFT", 4, 0)
    row.Tag:SetWidth(22)
    row.Item = UI.CreateCell(row, "GameFontHighlightSmall")
    row.Item:SetPoint("LEFT", row.Tag, "RIGHT", 4, 0)
    row.Item:SetWidth(240)
    row.Boss = UI.CreateCell(row, "GameFontDisableSmall", "RIGHT")
    row.Boss:SetPoint("RIGHT", -6, 0)
    row.Boss:SetWidth(140)
    row.Name = UI.CreateCell(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", row.Item, "RIGHT", 8, 0)
    row.Name:SetPoint("RIGHT", row.Boss, "LEFT", -6, 0)
    row:SetScript("OnEnter", LootTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    col.rows[i] = row
  end
  return row
end

-- Guests need a class; only ones that can play the column's role are offered.
local function GuestClass(owner, ev, name, target)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(("Class for %s"):format(name))
    for _, c in ipairs(ZR.ClassList()) do
      if not target.role or Raids.CanRole(c.file, target.role) then
        root:CreateButton(UI.ClassIcon(c.file, 14) .. " " .. ZR.ColorName(c.name, c.file), function()
          Raids.SetSignup(ev.id, name, target.st, target.role, nil, { c = c.file, g = true })
        end)
      end
    end
  end)
end

-- Guild members join as themselves; anyone else is a guest, asked for their class when it isn't known.
local function AddPlayer(ev, name, target, class, owner, forceGuest)
  local old = ev.signups[name]
  local member = not forceGuest and ZR.IsGuildMember(name)
  local info = ZR.RosterInfo(name)
  class = class or (info and info.classFile) or (old and old.c)
  if not member and not class then return GuestClass(owner, ev, name, target) end
  if target.role and class and not Raids.CanRole(class, target.role) then
    ZR.Msg(("%s can't play %s as a %s."):format(name, Raids.ROLE_NAMES[target.role], ClassName(class)))
    return
  end
  Raids.SetSignup(ev.id, name, target.st, target.role, nil, not member and { c = class, g = true } or nil)
  return true
end

-- Officers add a guild member, or anyone by name as a guest, straight into a column.
local function AddTo(btn)
  local ev, target = Selected(), btn.target
  if not ev or not target then return end
  local signed = {}
  for name, s in pairs(ev.signups or {}) do
    if s.st ~= "x" then signed[name] = s.c or true end
  end
  UI.PickMember(btn, function(name, guest)
    AddPlayer(ev, name, target, nil, btn, guest)
  end, signed, true)
end

local function CreateColumn(parent)
  local col = CreateFrame("Frame", nil, parent)
  col.Header = UI.CreateHeaderBar(col, "", 100)
  col.Header:SetPoint("TOPLEFT")
  col.Header:SetPoint("TOPRIGHT")
  col.Header:SetHeight(HEADER_HEIGHT)
  col.Icon = col.Header:CreateTexture(nil, "ARTWORK")
  col.Icon:SetSize(16, 16)
  col.Icon:SetPoint("LEFT", 6, 0)
  col.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  col.Header.Text:ClearAllPoints()
  col.Header.Text:SetPoint("LEFT", col.Icon, "RIGHT", 5, 0)
  col.Add = CreateFrame("Button", nil, col.Header)
  col.Add:SetSize(16, 16)
  col.Add:SetPoint("RIGHT", -4, 0)
  col.Add:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
  col.Add:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
  col.Add:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
  col.Add:SetScript("OnClick", AddTo)
  col.Add:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, "Add a player")
    GameTooltip:AddLine("Pick a guild member, or type a name to add someone from outside the guild.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  col.Add:SetScript("OnLeave", GameTooltip_Hide)
  col.Add:Hide()
  col.entries = {}
  return col
end

local function Entry(col, i)
  local e = col.entries[i]
  if not e then
    e = CreateFrame("Button", nil, col)
    e:SetHeight(ENTRY_HEIGHT)
    e:RegisterForClicks("RightButtonUp")
    e:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar", "ADD")
    e.Num = UI.CreateCell(e, "GameFontDisableSmall", "RIGHT")
    e.Num:SetPoint("LEFT", 0, 0)
    e.Num:SetWidth(16)
    e.Class = e:CreateTexture(nil, "ARTWORK")
    e.Class:SetSize(13, 13)
    e.Class:SetPoint("LEFT", e.Num, "RIGHT", 4, 0)
    e.Flag = e:CreateTexture(nil, "ARTWORK")
    e.Flag:SetSize(12, 12)
    e.Flag:SetPoint("RIGHT", -2, 0)
    e.Name = UI.CreateCell(e, "GameFontHighlightSmall")
    e.Name:SetPoint("LEFT", e.Class, "RIGHT", 4, 0)
    e.Name:SetPoint("RIGHT", e.Flag, "LEFT", -2, 0)
    e:SetScript("OnEnter", EntryTooltip)
    e:SetScript("OnLeave", GameTooltip_Hide)
    e:SetScript("OnClick", EntryMenu)
    e:ClearAllPoints()
    e:SetPoint("TOPLEFT", col, "TOPLEFT", 2, -HEADER_HEIGHT - 2 - (i - 1) * ENTRY_HEIGHT)
    e:SetPoint("RIGHT", col, "RIGHT", -2, 0)
    col.entries[i] = e
  end
  return e
end

-- flag(d) picks the small icon at the end of a row; returns the column's height.
local function Fill(col, title, icon, list, flag)
  col.Icon:SetTexture(icon)
  col.Header.Text:SetText(title)
  for i, d in ipairs(list) do
    local e = Entry(col, i)
    e.data = d
    e.Num:SetText(d.n)
    e.Class:SetAtlas(d.s.c and ("classicon-" .. d.s.c:lower()) or "classicon-warrior")
    e.Class:SetShown(d.s.c ~= nil)
    e.Name:SetText(ZR.ColorName(d.name, d.s.c) .. (d.s.g and " |cff888888guest|r" or ""))
    local f = flag and flag(d)
    e.Flag:SetShown(f ~= nil)
    if f then e.Flag:SetTexture(f) end
    e:Show()
  end
  for i = #list + 1, #col.entries do col.entries[i]:Hide() end
  local h = HEADER_HEIGHT + 4 + math.max(#list, 1) * ENTRY_HEIGHT
  col:SetHeight(h)
  return h
end

local function RoleTitle(ev, role, n)
  local name = Raids.ROLE_NAMES[role]
  local target = (role == "T" and ev.tanks) or (role == "H" and ev.healers) or 0
  if target > 0 then
    local color = n >= target and "|cff40ff40" or "|cffffffff"
    return ("%s %s%d/%d|r"):format(name, color, n, target)
  end
  return ("%s |cffffffff%d|r"):format(name, n)
end

local function LayoutRoster(ev)
  local width = view.Scroll:GetWidth()
  if width <= 0 then return end
  view.Content:SetWidth(width)
  local canAdd = ZR.IsOfficer() and not Raids.IsArchived(ev)
  local groups = { T = {}, H = {}, M = {}, R = {} }
  local others = { bench = {}, tent = {}, absent = {} }
  for _, d in ipairs(Raids.Signups(ev)) do
    if d.s.st == "in" or d.s.st == "late" then
      local list = groups[d.s.role] or groups.M
      list[#list + 1] = d
    elseif others[d.s.st] then
      local list = others[d.s.st]
      list[#list + 1] = d
    end
  end
  local colWidth = (width - GAP * 3) / 4
  local top = 0
  for i, role in ipairs(Raids.ROLES) do
    local col = view.RoleCols[i]
    col:ClearAllPoints()
    col:SetPoint("TOPLEFT", view.Content, "TOPLEFT", (i - 1) * (colWidth + GAP), 0)
    col:SetWidth(colWidth)
    col.Add.target = { st = "in", role = role }
    col.Add:SetShown(canAdd)
    local h = Fill(col, RoleTitle(ev, role, #groups[role]), Raids.ROLE_ICONS[role], groups[role], function(d)
      return d.s.st == "late" and LATE or nil
    end)
    top = math.max(top, h)
  end
  top = top + 20
  view.Divider:ClearAllPoints()
  view.Divider:SetPoint("TOPLEFT", view.Content, "TOPLEFT", 0, -(top - 10))
  view.Divider:SetPoint("RIGHT", view.Content, "RIGHT", 0, 0)
  colWidth = (width - GAP * 2) / 3
  local bottom = 0
  for i, sec in ipairs(SECTIONS) do
    local col = view.OtherCols[i]
    col:ClearAllPoints()
    col:SetPoint("TOPLEFT", view.Content, "TOPLEFT", (i - 1) * (colWidth + GAP), -top)
    col:SetWidth(colWidth)
    local list = others[sec.st]
    col.Add.target = { st = sec.st }
    col.Add:SetShown(canAdd)
    local h = Fill(col, ("%s |cffffffff%d|r"):format(sec.title, #list), sec.icon, list, function(d)
      return sec.st ~= "absent" and d.s.role and Raids.ROLE_ICONS[d.s.role] or nil
    end)
    bottom = math.max(bottom, h)
  end
  local reserves = Raids.Reserves(ev)
  table.sort(reserves, function(a, b)
    if a.k ~= b.k then return a.k == "H" end
    if a.b ~= b.b then return a.b < b.b end
    return a.n < b.n
  end)
  local col = view.LootCol
  col:SetShown(#reserves > 0)
  if #reserves == 0 then
    view.Content:SetHeight(top + bottom + 4)
    return
  end
  col:ClearAllPoints()
  col:SetPoint("TOPLEFT", view.Content, "TOPLEFT", 0, -(top + bottom + 12))
  col:SetWidth(width)
  col:SetHeight(HEADER_HEIGHT + 4 + #reserves * ENTRY_HEIGHT)
  col.Icon:SetTexture(LOOT_ICON)
  col.Header.Text:SetText(("Loot reserves |cffffffff%d|r"):format(#reserves))
  for i, r in ipairs(reserves) do
    local row = LootRow(col, i)
    row.data = r
    row.itemID = r.i
    row.Tag:SetText(KIND_TAGS[r.k] or "")
    row.Item:SetText(("|T%s:14:14|t |c%s%s|r"):format(Raids.ItemIcon(r.i), Raids.ItemColor(r.i), Raids.ItemName(r.i)))
    local info = ZR.RosterInfo(r.n)
    local signed = ev.signups[r.n]
    row.Name:SetText(ZR.ColorName(r.n, (info and info.classFile) or (signed and signed.c)))
    row.Boss:SetText(r.b)
    row:Show()
  end
  for i = #reserves + 1, #col.rows do col.rows[i]:Hide() end
  view.Content:SetHeight(top + bottom + 12 + HEADER_HEIGHT + 4 + #reserves * ENTRY_HEIGHT + 4)
end

-- Sign-up bar -----------------------------------------------------------

local function Note()
  return view.Note:GetText()
end

local function SignAs(role)
  local ev, mine = Selected(), nil
  if not ev then return end
  mine = Raids.Mine(ev)
  Raids.SetSignup(ev.id, nil, mine and mine.st == "late" and "late" or "in", role, Note())
end

local function SetStatus(st)
  local ev = Selected()
  if not ev then return end
  local mine = Raids.Mine(ev)
  local _, class = UnitClass("player")
  local role = mine and mine.role or Raids.LastRole(class)
  -- Late toggles back to a plain sign-up.
  if st == "late" and mine and mine.st == "late" then st = "in" end
  Raids.SetSignup(ev.id, nil, st, role, Note())
end

local function OpenSoftReserve(owner)
  local ev = Selected()
  if not ev then return end
  local me = ZR.PlayerName()
  UI.ToggleItemPicker(owner, {
    raid = ev.raid,
    title = "Soft reserve: pick your item",
    stay = true,
    above = true,
    canPick = function()
      local max = Raids.SoftLimit(ev)
      if Raids.SoftUsed(ev, me) >= max then
        return false, ("You've used your %d soft reserve%s. Remove one first."):format(max, max == 1 and "" or "s")
      end
      return true
    end,
    onPick = function(item, boss) Raids.AddSoftReserve(ev.id, item.id, boss) end,
    reserved = function()
      local out, mine = {}, Raids.Mine(ev)
      for i, r in ipairs(mine and mine.sr or {}) do
        out[#out + 1] = { r = { k = "S", i = r.i, b = r.b, n = me }, remove = function() Raids.RemoveSoftReserve(ev.id, i) end }
      end
      return out
    end,
    status = function()
      return ("%d of %d soft reserves used"):format(Raids.SoftUsed(ev, me), Raids.SoftLimit(ev))
    end,
  })
end

local function BarButton(text, icon, onClick)
  local b = UI.CreateButton(view.Detail, icon and (Icon(icon) .. " " .. text) or text, BUTTON_WIDTH, 22)
  -- Longer labels like Tentative get a wider button instead of crowding the edges.
  b:SetWidth(math.max(BUTTON_WIDTH, b:GetFontString():GetStringWidth() + 22))
  b:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    onClick()
  end)
  return b
end

local function UpdateBar(ev)
  local _, class = UnitClass("player")
  local mine = Raids.Mine(ev)
  local open = Raids.IsOpen(ev) or ZR.IsOfficer()
  for role, b in pairs(view.RoleButtons) do
    local can = Raids.CanRole(class, role)
    b:SetEnabled(open and can)
    b.why = not can and ("Your class can't sign up as " .. Raids.ROLE_NAMES[role] .. ".") or (not open and "Sign-ups are closed.") or nil
    if mine and (mine.st == "in" or mine.st == "late") and mine.role == role then b:LockHighlight() else b:UnlockHighlight() end
  end
  for st, b in pairs(view.StatusButtons) do
    b:SetEnabled(open and (st ~= "x" or mine ~= nil))
    b.why = not open and "Sign-ups are closed." or nil
    if mine and mine.st == st then b:LockHighlight() else b:UnlockHighlight() end
  end
  if not view.Note:HasFocus() then view.Note:SetText(mine and mine.note or "") end
  local me = ZR.PlayerName()
  local soft = view.SoftButton
  if soft.SetDefaultText then soft:SetDefaultText("SR Here") elseif soft.Text then soft.Text:SetText("SR Here") end
  soft.used = ("%d of %d soft reserves used"):format(Raids.SoftUsed(ev, me), Raids.SoftLimit(ev))
  soft.why = (not mine and "Sign up first, then pick your soft reserve.")
    or (mine.st == "absent" and "Absent players can't soft reserve.")
    or (not Raids.IsOpen(ev) and "Sign-ups are closed.") or nil
  soft:SetEnabled(soft.why == nil)
  if soft.why then UI.HideItemPicker(soft) end
end

-- Detail ----------------------------------------------------------------

local function Disarm()
  armed = nil
  if view then view.DeleteButton:SetText(DELETE or "Delete") end
end

-- Lays out just the buttons that apply, right to left above the raid.
local function ShowOfficerButtons(list)
  for _, btn in ipairs(view.OfficerButtons) do btn:Hide() end
  local prev
  for i = #list, 1, -1 do
    local btn = list[i]
    btn:ClearAllPoints()
    if prev then btn:SetPoint("RIGHT", prev, "LEFT", -2, 0) else btn:SetPoint("BOTTOMRIGHT", view.Detail, "TOPRIGHT", 0, 1) end
    btn:Show()
    prev = btn
  end
end

local function UpdateDescription(ev)
  local desc = ev.desc or ""
  local has = desc ~= ""
  view.DescBox:SetShown(has)
  view.Scroll:ClearAllPoints()
  view.Scroll:SetPoint("TOPLEFT", has and view.DescBox or view.Icon, "BOTTOMLEFT", 2, has and -10 or -21)
  view.Scroll:SetPoint("BOTTOMRIGHT", -30, 66)
  if has then view.Desc:SetText((desc:gsub("%s*\n%s*", "  "))) end
end

local function Announce()
  local ev = Selected()
  if not ev then return end
  if ZR.ChatLocked() then
    ZR.Msg("Chat is locked right now.")
    return
  end
  local c = Raids.Counts(ev)
  ZR.SendChat(("Raid sign-ups: %s (%d) on %s, %d/%d signed. Sign up in ZUGZUG Reborn, type /zr raids"):format(
    Raids.Title(ev), ev.size or 0, When(ev.start), c.going, ev.size or 0), "GUILD")
end

local function UpdateDetail()
  local ev = Selected()
  local officer = ZR.IsOfficer()
  local editing = view.Editor:IsShown()
  view.NewButton:SetShown(officer and not archive)
  if not officer or not ev then
    ShowOfficerButtons({})
  elseif Raids.IsArchived(ev) then
    ShowOfficerButtons(ev.arch and { view.RestoreButton, view.DeleteButton } or { view.DeleteButton })
  else
    ShowOfficerButtons({ view.EditButton, view.AnnounceButton, view.CloseButton, view.ArchiveButton })
  end
  view.Empty:SetShown(ev == nil and not editing)
  view.Body:SetShown(ev ~= nil and not editing)
  if not ev then
    local any = #(archive and Raids.Archived() or Raids.List()) > 0
    if archive then
      view.Empty.Text:SetText(any and "Pick a raid on the left." or "No archived raids.")
      view.Empty.Sub:SetText(any and "" or "Finished and archived raids show up here.")
    else
      view.Empty.Text:SetText(any and "Pick a raid on the left." or "No raids planned yet.")
      view.Empty.Sub:SetText(officer and not any and "Click New Raid to plan one." or "")
    end
    return
  end
  local info = Raids.Info(ev.raid)
  view.Icon:SetTexture(info.icon)
  view.Title:SetText(Raids.Title(ev))
  local sub = { (ev.raid == "other" and "Raid" or info.name), (ev.size or 0) .. " players" }
  if info.where then sub[#sub + 1] = info.where end
  view.Sub:SetText(table.concat(sub, "  -  "))
  local state = (Raids.IsArchived(ev) and "  |cff888888Archived|r") or (ev.closed and "  |cffff6060Sign-ups closed|r") or ""
  view.When:SetText(("%s  |cffaaaaaa(%s)|r%s"):format(Raids.When(ev.start, true), Countdown(ev.start), state))
  view.MapButton:SetShown(info.map ~= nil)
  view.Leader:SetText("Leader: |cffffffff" .. (ev.leader ~= "" and ev.leader or ev.by or "?") .. "|r")
  UpdateDescription(ev)
  local c = Raids.Counts(ev)
  local over = c.going > (ev.size or 0)
  view.Count:SetText((over and "|cffff6060%d|r/%d" or "%d/%d"):format(c.going, ev.size or 0))
  view.CloseButton:SetText(ev.closed and "Reopen" or "Close")
  LayoutRoster(ev)
  UpdateBar(ev)
end

function UI.UpdateRaids()
  if not view or not view:IsShown() then return end
  local list = archive and Raids.Archived() or Raids.List()
  local rows, found = {}, false
  for _, ev in ipairs(list) do
    rows[#rows + 1] = { ev = ev }
    if ev.id == selected then found = true end
  end
  if not found then selected = list[1] and list[1].id end
  view.List:SetRows(rows)
  view.NoRaids:SetText(archive and "No archived raids." or "No raids yet.")
  view.NoRaids:SetShown(#rows == 0)
  view.ListBox.Title:SetText(archive and "Archived raids" or "Raids")
  view.ArchiveToggle:SetText(archive and "Back to upcoming raids" or ("Archived raids (%d)"):format(#Raids.Archived()))
  UpdateDetail()
  UI.RefreshItemPicker()
end

function UI.ShowRaid(id)
  selected = id
  local ev = Raids.Get(id)
  archive = ev and Raids.IsArchived(ev) or false
  ZR.OpenPage("raids")
  UI.UpdateRaids()
end

local function BuildDetail(inset)
  local d = UI.CreateBox(view, nil)
  view.Detail = d
  d:SetPoint("TOPLEFT", view.ListBox, "TOPRIGHT", 14, 0)
  d:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -14, 12)
  d:SetBackdropColor(0, 0, 0, 0.7)

  view.Empty = CreateFrame("Frame", nil, d)
  view.Empty:SetAllPoints()
  view.Empty.Text = UI.Text(view.Empty, "GameFontNormalLarge")
  view.Empty.Text:SetPoint("CENTER", 0, 10)
  view.Empty.Sub = UI.Text(view.Empty, "GameFontHighlight")
  view.Empty.Sub:SetPoint("TOP", view.Empty.Text, "BOTTOM", 0, -8)

  local b = CreateFrame("Frame", nil, d)
  view.Body = b
  b:SetAllPoints()
  view.Icon = b:CreateTexture(nil, "ARTWORK")
  view.Icon:SetSize(36, 36)
  view.Icon:SetPoint("TOPLEFT", 10, -10)
  view.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  view.Count = UI.Text(b, "GameFontNormalHuge")
  view.Count:SetPoint("TOPRIGHT", -12, -8)
  view.CountLabel = UI.Text(b, "GameFontDisableSmall", "signed up")
  view.CountLabel:SetPoint("TOPRIGHT", view.Count, "BOTTOMRIGHT", 0, -1)
  -- Leader sits under the count, where the header has room to spare.
  view.Leader = UI.Text(b, "GameFontNormalSmall")
  view.Leader:SetPoint("TOPRIGHT", view.CountLabel, "BOTTOMRIGHT", 0, -3)
  view.Leader:SetJustifyH("RIGHT")
  view.Title = UI.Text(b, "GameFontNormalLarge")
  view.Title:SetPoint("TOPLEFT", view.Icon, "TOPRIGHT", 8, 0)
  view.Title:SetPoint("RIGHT", view.Count, "LEFT", -10, 0)
  view.Title:SetJustifyH("LEFT")
  view.Title:SetWordWrap(false)
  view.Sub = UI.Text(b, "GameFontDisableSmall")
  view.Sub:SetPoint("TOPLEFT", view.Title, "BOTTOMLEFT", 0, -2)
  view.MapButton = UI.CreateRaidMapButton(b, function()
    local ev = Selected()
    return ev and Raids.Info(ev.raid)
  end)
  view.MapButton:SetSize(16, 16)
  view.MapButton:SetPoint("LEFT", view.Sub, "RIGHT", 6, 0)
  view.When = UI.Text(b, "GameFontHighlight")
  view.When:SetPoint("TOPLEFT", view.Sub, "BOTTOMLEFT", 0, -3)
  -- One slim line so the sign-ups get the room; hovering shows the full text.
  view.DescBox = CreateFrame("Frame", nil, b)
  -- Clears the date line under the title with a little room to spare.
  view.DescBox:SetPoint("TOPLEFT", view.Icon, "BOTTOMLEFT", -2, -17)
  view.DescBox:SetPoint("RIGHT", -10, 0)
  view.DescBox:SetHeight(20)
  view.DescBox:EnableMouse(true)
  local tint = view.DescBox:CreateTexture(nil, "BACKGROUND")
  tint:SetAllPoints()
  tint:SetColorTexture(1, 0.82, 0, 0.1)
  local edge = view.DescBox:CreateTexture(nil, "BORDER")
  edge:SetPoint("TOPLEFT")
  edge:SetPoint("BOTTOMLEFT")
  edge:SetWidth(2)
  edge:SetColorTexture(1, 0.82, 0, 0.8)
  view.DescIcon = view.DescBox:CreateTexture(nil, "ARTWORK")
  view.DescIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
  view.DescIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  view.DescIcon:SetSize(14, 14)
  view.DescIcon:SetPoint("LEFT", 7, 0)
  view.Desc = UI.Text(view.DescBox, "GameFontHighlightSmall")
  view.Desc:SetPoint("LEFT", view.DescIcon, "RIGHT", 6, 0)
  view.Desc:SetPoint("RIGHT", -6, 0)
  view.Desc:SetJustifyH("LEFT")
  view.Desc:SetWordWrap(false)
  view.DescBox:SetScript("OnEnter", function(self)
    local ev = Selected()
    if not ev or (ev.desc or "") == "" then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip_SetTitle(GameTooltip, Raids.Title(ev))
    for _, line in ipairs(WrapLines(ev.desc)) do GameTooltip:AddLine(line ~= "" and line or " ", 1, 1, 1) end
    GameTooltip:Show()
  end)
  view.DescBox:SetScript("OnLeave", GameTooltip_Hide)

  -- Sign-up bar along the bottom.
  view.StatusButtons = {
    late = BarButton("Late", LATE, function() SetStatus("late") end),
    tent = BarButton("Tentative", WAITING, function() SetStatus("tent") end),
    bench = BarButton("Bench", BENCH, function() SetStatus("bench") end),
    absent = BarButton("Absent", NOT_READY, function() SetStatus("absent") end),
    x = BarButton(REMOVE or "Remove", nil, function() SetStatus("x") end),
  }
  local prev
  for _, st in ipairs({ "late", "tent", "bench", "absent", "x" }) do
    local btn = view.StatusButtons[st]
    btn:SetParent(b)
    if prev then btn:SetPoint("LEFT", prev, "RIGHT", 4, 0) else btn:SetPoint("BOTTOMLEFT", 12, 10) end
    prev = btn
  end
  local label = UI.Text(b, "GameFontNormalSmall", "Sign up as")
  label:SetPoint("BOTTOMLEFT", view.StatusButtons.late, "TOPLEFT", 2, 8)
  view.RoleButtons = {}
  prev = nil
  for _, role in ipairs(Raids.ROLES) do
    local btn = BarButton(Raids.ROLE_NAMES[role], Raids.ROLE_ICONS[role], function() SignAs(role) end)
    btn:SetParent(b)
    if prev then btn:SetPoint("LEFT", prev, "RIGHT", 4, 0) else btn:SetPoint("LEFT", label, "RIGHT", 8, 0) end
    view.RoleButtons[role] = btn
    prev = btn
  end
  local all = {}
  for _, btn in pairs(view.RoleButtons) do all[#all + 1] = btn end
  for _, btn in pairs(view.StatusButtons) do all[#all + 1] = btn end
  for _, btn in ipairs(all) do
    UI.SetButtonTooltip(btn, function(self) return self.why and "Can't do that" or nil, self.why end)
  end
  -- Soft reserving sits with the other things players do for themselves.
  view.SoftButton = CreateFrame("DropdownButton", nil, b, "WowStyle1DropdownTemplate")
  view.SoftButton:SetPoint("LEFT", view.StatusButtons.x, "RIGHT", 8, 0)
  view.SoftButton:SetPoint("RIGHT", -14, 0)
  view.SoftButton:SetMotionScriptsWhileDisabled(true)
  view.SoftButton:HookScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and self:IsEnabled() then OpenSoftReserve(self) end
  end)
  view.SoftButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip_SetTitle(GameTooltip, "Soft reserve")
    GameTooltip:AddLine(self.why or "Pick the item you want most. If it drops, only those who reserved it roll for it.", 1, 1, 1, true)
    if not self.why and self.used then GameTooltip:AddLine(self.used, 0.6, 0.8, 1) end
    GameTooltip:Show()
  end)
  view.SoftButton:SetScript("OnLeave", GameTooltip_Hide)
  view.NoteLabel = UI.Text(b, "GameFontNormalSmall", "Note")
  view.NoteLabel:SetPoint("LEFT", view.RoleButtons.R, "RIGHT", 12, 0)
  view.Note = UI.CreateInput(b, 100, 20)
  view.Note:SetMaxLetters(40)
  view.Note:SetPoint("LEFT", view.NoteLabel, "RIGHT", 8, 0)
  view.Note:SetPoint("RIGHT", -14, 0)
  -- Saves a moment after typing stops; without a sign-up it goes along with the next one.
  local noteFor, noteTimer
  local function SaveNote()
    if noteTimer then noteTimer:Cancel() end
    noteTimer = nil
    local ev = noteFor and Raids.Get(noteFor)
    local mine = ev and Raids.Mine(ev)
    local text = view.Note:GetText()
    if mine and text ~= (mine.note or "") then Raids.SetSignup(ev.id, nil, mine.st, mine.role, text) end
  end
  view.Note:HookScript("OnTextChanged", function(self, user)
    if not user then return end
    local ev = Selected()
    noteFor = ev and ev.id
    if noteTimer then noteTimer:Cancel() end
    noteTimer = C_Timer.NewTimer(1.5, SaveNote)
  end)
  view.Note:HookScript("OnEditFocusLost", function() if noteTimer then SaveNote() end end)
  view.Note:SetScript("OnEnterPressed", view.Note.ClearFocus)

  view.Scroll = CreateFrame("ScrollFrame", nil, b)
  view.Scroll:SetPoint("TOPLEFT", view.Leader, "BOTTOMLEFT", 0, -10)
  view.Scroll:SetPoint("BOTTOMRIGHT", -30, 66)
  view.ScrollBar = CreateFrame("EventFrame", nil, b, "MinimalScrollBar")
  view.ScrollBar:SetPoint("TOPLEFT", view.Scroll, "TOPRIGHT", 8, 0)
  view.ScrollBar:SetPoint("BOTTOMLEFT", view.Scroll, "BOTTOMRIGHT", 8, 0)
  ScrollUtil.InitScrollFrameWithScrollBar(view.Scroll, view.ScrollBar)
  view.Content = CreateFrame("Frame", nil, view.Scroll)
  view.Content:SetSize(1, 1)
  view.Scroll:SetScrollChild(view.Content)
  view.Scroll:SetClipsChildren(true)
  view.Scroll:SetScript("OnSizeChanged", function()
    local ev = Selected()
    if ev then LayoutRoster(ev) end
  end)
  view.RoleCols, view.OtherCols = {}, {}
  for i = 1, 4 do view.RoleCols[i] = CreateColumn(view.Content) end
  view.Divider = view.Content:CreateTexture(nil, "ARTWORK")
  view.Divider:SetHeight(1)
  view.Divider:SetColorTexture(1, 0.82, 0, 0.25)
  for i = 1, 3 do view.OtherCols[i] = CreateColumn(view.Content) end
  view.LootCol = CreateColumn(view.Content)
  view.LootCol:Hide()
end

local function OfficerButton(text, width, onClick)
  local btn = UI.CreateButton(view, text, width, 20)
  btn:SetScript("OnClick", function(self)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    onClick(self)
  end)
  return btn
end

function UI.BuildRaids(parent, inset)
  view = CreateFrame("Frame", nil, parent)
  view:SetAllPoints(parent)

  view.ListBox = UI.CreateBox(view, "Raids")
  view.ListBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -26)
  view.ListBox:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 14, 12)
  view.ListBox:SetWidth(LIST_WIDTH)
  view.List = UI.CreateTable(view.ListBox, { { title = "", width = 0 } }, nil, 46, InitRow)
  view.List:SetPoint("TOPLEFT", 6, -6)
  view.List:SetPoint("BOTTOMRIGHT", -6, 34)
  view.List.Header:Hide()
  view.List.ScrollBox:SetPoint("TOPLEFT", view.List, "TOPLEFT", 0, 0)
  view.NoRaids = UI.Text(view.ListBox, "GameFontDisable", "No raids yet.")
  view.NoRaids:SetPoint("CENTER", 0, 14)
  view.ArchiveToggle = UI.CreateButton(view.ListBox, "", 100, 22)
  view.ArchiveToggle:SetPoint("BOTTOMLEFT", 8, 8)
  view.ArchiveToggle:SetPoint("BOTTOMRIGHT", -8, 8)
  view.ArchiveToggle:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    archive = not archive
    selected = nil
    view.Editor:Hide()
    UI.UpdateRaids()
  end)

  view.NewButton = OfficerButton("New Raid", 90, function() UI.OpenRaidEditor(nil) end)
  view.NewButton:SetPoint("BOTTOMRIGHT", view.ListBox, "TOPRIGHT", 0, 1)

  BuildDetail(inset)

  view.DeleteButton = OfficerButton(DELETE or "Delete", 74, function(self)
    local ev = Selected()
    if not ev then return end
    if not armed then
      local token = {}
      armed = token
      self:SetText("Sure?")
      C_Timer.After(3, function() if armed == token then Disarm() end end)
      return
    end
    Disarm()
    Raids.Delete(ev.id)
  end)
  view.DeleteButton:SetPoint("BOTTOMRIGHT", view.Detail, "TOPRIGHT", 0, 1)
  view.CloseButton = OfficerButton("Close", 74, function()
    local ev = Selected()
    if ev then Raids.SetClosed(ev.id, not ev.closed) end
  end)
  view.CloseButton:SetPoint("RIGHT", view.DeleteButton, "LEFT", -2, 0)
  view.AnnounceButton = OfficerButton("Announce", 84, Announce)
  view.AnnounceButton:SetPoint("RIGHT", view.CloseButton, "LEFT", -2, 0)
  UI.SetButtonTooltip(view.AnnounceButton, function()
    return "Announce in guild chat", "Posts the raid, its time and how many have signed up."
  end)
  view.EditButton = OfficerButton(EDIT or "Edit", 74, function()
    local ev = Selected()
    if ev then UI.OpenRaidEditor(ev) end
  end)
  view.EditButton:SetPoint("RIGHT", view.AnnounceButton, "LEFT", -2, 0)
  view.ArchiveButton = OfficerButton("Archive", 74, function()
    local ev = Selected()
    if ev then Raids.SetArchived(ev.id, true) end
  end)
  UI.SetButtonTooltip(view.ArchiveButton, function()
    return "Archive", "Moves it to Archived raids at the bottom of the list. Finished raids go there on their own."
  end)
  view.RestoreButton = OfficerButton("Restore", 74, function()
    local ev = Selected()
    if not ev then return end
    Raids.SetArchived(ev.id, false)
    archive = false
    UI.UpdateRaids()
  end)
  UI.SetButtonTooltip(view.DeleteButton, function()
    return "Delete for good", "Removes it for the whole guild. Click twice."
  end)
  view.OfficerButtons = { view.EditButton, view.AnnounceButton, view.CloseButton, view.ArchiveButton, view.RestoreButton, view.DeleteButton }

  view.Editor = UI.BuildRaidEditor(view, Select)
  view.Editor:SetAllPoints(view.Detail)
  view.Editor:SetFrameLevel(view.Detail:GetFrameLevel() + 20)
  -- The raid underneath would show through, so it hides while editing.
  view.Editor:HookScript("OnShow", function()
    view.Body:Hide()
    view.Empty:Hide()
  end)
  view.Editor:HookScript("OnHide", function() UI.UpdateRaids() end)

  view.Update = UI.UpdateRaids
  view:SetScript("OnShow", function()
    selected = selected or ZR.DB().raidSelected
    UI.UpdateRaids()
    Raids.Ask()
  end)
  view:SetScript("OnHide", function()
    Disarm()
    view.Editor:Hide()
    view.Note:ClearFocus()
  end)
  -- Keeps countdowns current while the tab is open.
  view:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 30 then return end
    self.elapsed = 0
    UI.UpdateRaids()
  end)
  ZR.On("RaidsChanged", UI.UpdateRaids)
  ZR.On("OfficerChanged", UI.UpdateRaids)
  -- Built hidden, so the first Show runs OnShow and fills everything in.
  view:Hide()
  return view
end

local ADD_TARGETS = {
  { st = "in", role = "T" }, { st = "in", role = "H" }, { st = "in", role = "M" }, { st = "in", role = "R" },
  { st = "tent", title = "Tentative", icon = WAITING }, { st = "bench", title = "Bench", icon = BENCH },
}

local function ContextClass(data, name)
  local unit = data.unit
  if unit and UnitExists(unit) and UnitIsPlayer(unit) then
    local _, class = UnitClass(unit)
    if class and not ZR.IsSecret(class) then return class end
  end
  if data.guid and GetPlayerInfoByGUID then
    local ok, _, class = pcall(GetPlayerInfoByGUID, data.guid)
    if ok and class and not ZR.IsSecret(class) then return class end
  end
  local info = ZR.RosterInfo(name)
  return info and info.classFile
end

-- Right-clicking a player anywhere lets officers put them in an upcoming raid.
if Menu and Menu.ModifyMenu then
  local tags = { "PLAYER", "PARTY", "RAID_PLAYER", "FRIEND", "GUILD", "COMMUNITIES_GUILD_MEMBER", "RECENT_ALLY" }
  for _, tag in ipairs(tags) do
    Menu.ModifyMenu("MENU_UNIT_" .. tag, function(owner, root, data)
      local name = data and data.name
      if not ZR.IsOfficer() or type(name) ~= "string" or ZR.IsSecret(name) or name == "" then return end
      name = ZR.StripRealm(name)
      local raids = Raids.List()
      if name == ZR.PlayerName() or #raids == 0 then return end
      local class = ContextClass(data, name)
      root:CreateDivider()
      root:CreateTitle(ZR.TITLE)
      local add = root:CreateButton("Add to raid")
      for _, ev in ipairs(raids) do
        local sub = add:CreateButton(("|T%s:14:14|t %s  |cffaaaaaa%s|r"):format(Raids.Info(ev.raid).icon, Raids.Title(ev), Raids.When(ev.start)))
        for _, target in ipairs(ADD_TARGETS) do
          if not target.role or not class or Raids.CanRole(class, target.role) then
            local label = target.role and (Icon(Raids.ROLE_ICONS[target.role]) .. " " .. Raids.ROLE_NAMES[target.role])
              or (Icon(target.icon) .. " " .. target.title)
            sub:CreateButton(label, function()
              if AddPlayer(ev, name, target, class, owner or UIParent) then
                ZR.Msg(("Added %s to %s."):format(name, Raids.Title(ev)))
              end
            end)
          end
        end
      end
    end)
  end
end

ZR.On("RaidSoon", function(ev, mins)
  UI.Toast({
    icon = Raids.Info(ev.raid).icon,
    title = Raids.Title(ev),
    text = ("starts in %d minute%s"):format(mins, mins == 1 and "" or "s"),
    button = { label = "Open", onClick = function() UI.ShowRaid(ev.id) end },
  })
end)
