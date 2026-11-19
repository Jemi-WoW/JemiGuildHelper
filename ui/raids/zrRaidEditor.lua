local _, ZR = ...
local UI = ZR.UI
local Raids = ZR.Raids

local DAYS = 28
local MENU_HEIGHT = 300

local ed
local form = {}

local function Noon(offset)
  local t = date("*t")
  t.hour, t.min, t.sec = 12, 0, 0
  return date("*t", time(t) + offset * 86400)
end

local function DayKey(t)
  return t.year * 10000 + t.month * 100 + t.day
end

local function DayLabel(t, offset)
  local label = date("%a %d %b", time({ year = t.year, month = t.month, day = t.day, hour = 12 }))
  if offset == 0 then return "Today, " .. label end
  if offset == 1 then return "Tomorrow, " .. label end
  return label
end

local function Start()
  local d = form.day
  return time({ year = d.year, month = d.month, day = d.day, hour = form.hour, min = form.min, sec = 0 })
end

local function Label(text, x, y)
  local fs = UI.Text(ed, "GameFontNormalSmall", text)
  fs:SetPoint("TOPLEFT", x, y)
  return fs
end

local function Dropdown(width, x, y)
  local dd = CreateFrame("DropdownButton", nil, ed, "WowStyle1DropdownTemplate")
  dd:SetWidth(width)
  if x then dd:SetPoint("TOPLEFT", x, y) end
  return dd
end

local function Input(width, maxLetters, x, y)
  local e = UI.CreateInput(ed, width, 20)
  e:SetMaxLetters(maxLetters)
  e:SetPoint("TOPLEFT", x, y)
  return e
end

local function Scroll(root)
  if root.SetScrollMode then root:SetScrollMode(MENU_HEIGHT) end
end

local function SetTargets()
  local t = Raids.TARGETS[form.size] or Raids.TARGETS[20]
  ed.Tanks:SetNumber(t[1])
  ed.Healers:SetNumber(t[2])
end

local function UpdateNote()
  local info = Raids.Info(form.raid)
  if info.note then
    ed.Note:SetText("|cffff8040" .. info.note .. "|r")
  else
    ed.Note:SetText(info.where and ("In " .. info.where) or "")
  end
  ed.MapButton:SetShown(info.map ~= nil)
end

-- The AM/PM picker only shows on a 12 hour clock, and the clock picker follows it.
local function UpdateClock()
  local twelve = Raids.Use12h()
  ed.AmPm:SetShown(twelve)
  ed.Clock:ClearAllPoints()
  ed.Clock:SetPoint("LEFT", twelve and ed.AmPm or ed.Min, "RIGHT", 10, 0)
  for _, dd in ipairs({ ed.Hour, ed.AmPm, ed.Clock }) do dd:GenerateMenu() end
end

local KINDS = { S = "Soft reserve", H = "Hard reserve" }

local function UpdateReserves()
  for kind, dd in pairs(ed.Reserve) do
    local n = 0
    for _, r in ipairs(form.res) do
      if r.k == kind then n = n + 1 end
    end
    local text = n > 0 and ("%s (%d)"):format(KINDS[kind], n) or KINDS[kind]
    if dd.SetDefaultText then dd:SetDefaultText(text) elseif dd.Text then dd.Text:SetText(text) end
  end
end

-- Raid sign-ups come first in the member list, since reserves are for those raiding.
local function SignedUp()
  local ev = form.id and Raids.Get(form.id)
  local set = {}
  for name, s in pairs(ev and ev.signups or {}) do
    if s.st ~= "x" and s.st ~= "absent" then set[name] = s.c or true end
  end
  return set
end

local function ToggleItems(owner, kind)
  UI.ToggleItemPicker(owner, {
    raid = form.raid,
    title = KINDS[kind] .. ": pick the item",
    onPick = function(item, boss)
      UI.PickMember(owner, function(name)
        form.res[#form.res + 1] = { k = kind, i = item.id, b = boss, n = name }
        UpdateReserves()
      end, SignedUp())
    end,
    reserved = function()
      local out = {}
      for i, r in ipairs(form.res) do
        if r.k == kind then
          out[#out + 1] = { r = r, remove = function()
            table.remove(form.res, i)
            UpdateReserves()
          end }
        end
      end
      return out
    end,
  })
end

local function SetupRaid(dd)
  dd:SetupMenu(function(_, root)
    for _, r in ipairs(Raids.LIST) do
      local label = ("|T%s:16:16|t %s"):format(r.icon, r.key == "other" and "Other raid or event" or (r.name .. " (" .. r.size .. ")"))
      root:CreateRadio(label, function() return form.raid == r.key end, function()
        if form.raid ~= r.key and #form.res > 0 then
          -- Reserves name the old raid's bosses, so they don't carry over.
          wipe(form.res)
          UpdateReserves()
          ed.Error:SetText("Loot reserves were cleared for the new raid.")
        end
        -- The raid's own note fills an empty description, and swaps out with the raid.
        local text = ed.Desc:GetText()
        if text == "" or text == form.autoDesc then
          form.autoDesc = r.note
          ed.Desc:SetText(r.note or "")
        end
        form.raid = r.key
        Raids.PreloadLoot(r.key)
        if r.key ~= "other" then
          form.size = r.size
          ed.Size:GenerateMenu()
          SetTargets()
        end
        UpdateNote()
      end)
    end
  end)
end

local function SetupSize(dd)
  dd:SetupMenu(function(_, root)
    for _, size in ipairs(Raids.SIZES) do
      root:CreateRadio(size .. " players", function() return form.size == size end, function()
        form.size = size
        SetTargets()
      end)
    end
  end)
end

local function SetupDay(dd)
  dd:SetupMenu(function(_, root)
    Scroll(root)
    local days = {}
    for i = 0, DAYS - 1 do days[#days + 1] = { t = Noon(i), offset = i } end
    -- An edited raid in the past keeps its own day as a choice.
    if form.day and DayKey(form.day) < DayKey(days[1].t) then table.insert(days, 1, { t = form.day }) end
    for _, d in ipairs(days) do
      root:CreateRadio(DayLabel(d.t, d.offset), function() return form.day and DayKey(form.day) == DayKey(d.t) end, function()
        form.day = d.t
      end)
    end
  end)
end

local function SetupHour(dd)
  dd:SetupMenu(function(_, root)
    Scroll(root)
    if Raids.Use12h() then
      local pm = form.hour >= 12
      for i = 0, 11 do
        local h = i + (pm and 12 or 0)
        root:CreateRadio(tostring(i == 0 and 12 or i), function() return form.hour == h end, function() form.hour = h end)
      end
      return
    end
    for h = 0, 23 do
      root:CreateRadio(("%02d"):format(h), function() return form.hour == h end, function() form.hour = h end)
    end
  end)
end

local function SetupMinute(dd)
  dd:SetupMenu(function(_, root)
    Scroll(root)
    for m = 0, 55, 5 do
      root:CreateRadio(("%02d"):format(m), function() return form.min == m end, function() form.min = m end)
    end
  end)
end

local function SetupAmPm(dd)
  dd:SetupMenu(function(_, root)
    for _, pm in ipairs({ false, true }) do
      root:CreateRadio(pm and "PM" or "AM", function() return (form.hour >= 12) == pm end, function()
        form.hour = form.hour % 12 + (pm and 12 or 0)
        ed.Hour:GenerateMenu()
      end)
    end
  end)
end

local function SetupClock(dd)
  dd:SetupMenu(function(_, root)
    for _, hours in ipairs({ 24, 12 }) do
      root:CreateRadio(hours .. "h clock", function() return (hours == 12) == Raids.Use12h() end, function()
        Raids.SetClock(hours)
        UpdateClock()
      end)
    end
  end)
end

local function Save()
  local start = Start()
  if not form.id and start <= ZR.Now() then
    ed.Error:SetText("Pick a time that hasn't passed yet.")
    return
  end
  local leader = ed.Leader:GetMember() or ""
  local id = Raids.Save({
    id = form.id,
    raid = form.raid,
    size = form.size,
    start = start,
    leader = leader ~= "" and leader or ZR.PlayerName(),
    res = form.res,
    srMax = form.srMax,
    tanks = ed.Tanks:GetNumber(),
    healers = ed.Healers:GetNumber(),
    title = ed.Title:GetText(),
    desc = ed.Desc:GetText(),
  })
  ZR.DB().raidLast = { raid = form.raid, hour = form.hour, min = form.min }
  ed:Hide()
  if id and ed.onSaved then ed.onSaved(id) end
end

function UI.BuildRaidEditor(parent, onSaved)
  ed = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  ed:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  ed:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
  ed:SetBackdropBorderColor(1, 0.82, 0, 0.9)
  ed:EnableMouse(true)
  ed.onSaved = onSaved

  ed.Heading = UI.Text(ed, "GameFontNormalLarge")
  ed.Heading:SetPoint("TOPLEFT", 16, -12)

  Label("Raid", 16, -34)
  ed.Raid = Dropdown(230, 16, -46)
  SetupRaid(ed.Raid)
  ed.MapButton = UI.CreateRaidMapButton(ed, function() return Raids.Info(form.raid) end)
  ed.MapButton:SetPoint("LEFT", ed.Raid, "RIGHT", 6, 0)
  Label("Size", 290, -34)
  ed.Size = Dropdown(110, 290, -46)
  SetupSize(ed.Size)
  ed.Note = UI.Text(ed, "GameFontHighlightSmall")
  ed.Note:SetPoint("LEFT", ed.Size, "RIGHT", 12, 0)
  ed.Note:SetPoint("RIGHT", -16, 0)
  ed.Note:SetJustifyH("LEFT")

  Label("Day", 16, -76)
  ed.Day = Dropdown(180, 16, -88)
  SetupDay(ed.Day)
  Label("Time (your clock)", 206, -76)
  ed.Hour = Dropdown(64, 206, -88)
  SetupHour(ed.Hour)
  ed.Colon = UI.Text(ed, "GameFontNormal", ":")
  ed.Colon:SetPoint("LEFT", ed.Hour, "RIGHT", 3, 0)
  ed.Min = Dropdown(64)
  ed.Min:SetPoint("LEFT", ed.Hour, "RIGHT", 12, 0)
  SetupMinute(ed.Min)
  ed.AmPm = Dropdown(64)
  ed.AmPm:SetPoint("LEFT", ed.Min, "RIGHT", 6, 0)
  SetupAmPm(ed.AmPm)
  ed.Clock = Dropdown(96)
  SetupClock(ed.Clock)

  Label("Title (optional)", 16, -118)
  ed.Title = Input(190, 40, 22, -132)
  Label("Leader", 226, -118)
  ed.Leader = UI.CreateMemberPicker(ed, 170)
  ed.Leader:SetPoint("TOPLEFT", 226, -130)
  Label("Tanks", 412, -118)
  ed.Tanks = Input(36, 2, 418, -132)
  ed.Tanks:SetNumeric(true)
  Label("Healers", 468, -118)
  ed.Healers = Input(36, 2, 474, -132)
  ed.Healers:SetNumeric(true)

  -- Stretches to the space left, always stopping above the buttons; reserves sit beside it.
  local box = UI.CreateBox(ed, "Description")
  box:SetPoint("TOPLEFT", 16, -176)
  box:SetPoint("BOTTOMRIGHT", -200, 42)
  local label = UI.Text(ed, "GameFontNormal", "Loot reserves")
  label:SetPoint("BOTTOMLEFT", box, "TOPRIGHT", 18, 2)
  ed.Reserve = {}
  local prev
  for _, kind in ipairs({ "S", "H" }) do
    local dd = Dropdown(170)
    if prev then dd:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -8) else dd:SetPoint("TOPLEFT", box, "TOPRIGHT", 14, 0) end
    dd:HookScript("OnMouseDown", function(self, button)
      if button == "LeftButton" then ToggleItems(self, kind) end
    end)
    ed.Reserve[kind] = dd
    prev = dd
  end
  -- How many items each player may soft reserve for themselves from the raid view.
  ed.SoftMax = Dropdown(170)
  ed.SoftMax:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -8)
  ed.SoftMax:SetupMenu(function(_, root)
    for n = 1, 3 do
      root:CreateRadio(("%d soft reserve%s each"):format(n, n == 1 and "" or "s"), function() return form.srMax == n end, function()
        form.srMax = n
      end)
    end
  end)
  local scroll = CreateFrame("ScrollFrame", nil, box)
  scroll:SetPoint("TOPLEFT", 8, -6)
  scroll:SetPoint("BOTTOMRIGHT", -24, 6)
  local bar = CreateFrame("EventFrame", nil, box, "MinimalScrollBar")
  bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
  ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
  ed.Desc = CreateFrame("EditBox", nil, scroll)
  ed.Desc:SetMultiLine(true)
  ed.Desc:SetAutoFocus(false)
  ed.Desc:SetMaxLetters(Raids.DESC_MAX)
  ed.Desc:SetFontObject("GameFontHighlightSmall")
  ed.Desc:SetSize(100, 20)
  ed.Desc:SetScript("OnEscapePressed", ed.Desc.ClearFocus)
  scroll:SetScrollChild(ed.Desc)
  -- Same counter as the recruitment boxes.
  ed.DescCount = UI.Text(ed, "GameFontHighlightSmall")
  ed.DescCount:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", -4, 3)
  ed.Desc:HookScript("OnTextChanged", function(self)
    local n = #self:GetText()
    ed.DescCount:SetText((n > Raids.DESC_MAX and "|cffff4040" or "|cffbbbbbb") .. n .. "/" .. Raids.DESC_MAX .. "|r")
  end)
  scroll:SetScript("OnSizeChanged", function(self, width) ed.Desc:SetWidth(width) end)
  -- Keeps the line being typed in view.
  ed.Desc:SetScript("OnCursorChanged", function(_, _, y, _, h)
    local top, offset, height = -y, scroll:GetVerticalScroll(), scroll:GetHeight()
    if top < offset then
      scroll:SetVerticalScroll(top)
    elseif top + h > offset + height then
      scroll:SetVerticalScroll(top + h - height)
    end
  end)
  box:EnableMouse(true)
  box:SetScript("OnMouseDown", function() ed.Desc:SetFocus() end)

  ed.Save = UI.CreateButton(ed, SAVE or "Save", 100, 22)
  ed.Save:SetPoint("BOTTOMRIGHT", -16, 12)
  ed.Save:SetScript("OnClick", Save)
  ed.Cancel = UI.CreateButton(ed, CANCEL or "Cancel", 100, 22)
  ed.Cancel:SetPoint("RIGHT", ed.Save, "LEFT", -6, 0)
  ed.Cancel:SetScript("OnClick", function() ed:Hide() end)
  ed.Error = UI.Text(ed, "GameFontRedSmall")
  ed.Error:SetPoint("BOTTOMLEFT", 18, 17)

  ed:SetScript("OnHide", function()
    ed.Title:ClearFocus()
    ed.Desc:ClearFocus()
    UI.HideItemPicker()
  end)
  ed:Hide()
  return ed
end

-- ev nil plans a new raid, starting from the last one planned.
function UI.OpenRaidEditor(ev)
  wipe(form)
  if ev then
    local t = date("*t", ev.start)
    form.id, form.raid, form.size = ev.id, ev.raid, ev.size
    form.day, form.hour, form.min = t, t.hour, t.min - t.min % 5
    ed.Title:SetText(ev.title or "")
    ed.Leader:SetMember(ev.leader ~= "" and ev.leader or ZR.PlayerName())
    ed.Desc:SetText(ev.desc or "")
    ed.Desc:SetCursorPosition(0)
    ed.Heading:SetText("Edit raid")
  else
    local last = ZR.DB().raidLast or {}
    form.raid = last.raid or Raids.LIST[1].key
    form.size = Raids.Info(form.raid).size
    form.hour, form.min = last.hour or 19, last.min or 30
    local today = date("*t")
    local passed = today.hour * 60 + today.min >= form.hour * 60 + form.min
    form.day = Noon(passed and 1 or 0)
    ed.Title:SetText("")
    ed.Leader:SetMember(ZR.PlayerName())
    form.autoDesc = Raids.Info(form.raid).note
    ed.Desc:SetText(form.autoDesc or "")
    ed.Heading:SetText("Plan a raid")
  end
  ed.Error:SetText("")
  for _, dd in ipairs({ ed.Raid, ed.Size, ed.Day, ed.Min }) do dd:GenerateMenu() end
  UpdateClock()
  if ev then
    ed.Tanks:SetNumber(ev.tanks or 0)
    ed.Healers:SetNumber(ev.healers or 0)
  else
    SetTargets()
  end
  form.srMax = ev and ev.srMax or 1
  ed.SoftMax:GenerateMenu()
  form.res = {}
  for _, r in ipairs(ev and ev.res or {}) do form.res[#form.res + 1] = { k = r.k, i = r.i, b = r.b, n = r.n } end
  UpdateReserves()
  Raids.PreloadLoot(form.raid)
  UpdateNote()
  ed:Show()
end
