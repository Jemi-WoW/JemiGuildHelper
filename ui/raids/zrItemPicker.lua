local _, ZR = ...
local UI = ZR.UI
local Raids = ZR.Raids

-- The boss and item list for loot reserves, shared by the raid editor and the raid view.
local items
local opts = {}

function UI.ItemLabel(id, size)
  return ("|T%s:%d:%d|t |c%s%s|r"):format(Raids.ItemIcon(id), size, size, Raids.ItemColor(id), Raids.ItemName(id))
end

-- Bosses fold open on click, or on their own while searching or when there's only one.
local function Rows(filter)
  local rows = {}
  local bosses = Raids.Bosses(opts.raid)
  local single = #bosses == 2
  for _, boss in ipairs(bosses) do
    local bossHit = filter ~= "" and boss.name:lower():find(filter, 1, true)
    local matched = {}
    for _, it in ipairs(boss.all) do
      if filter == "" or bossHit or Raids.ItemName(it.id):lower():find(filter, 1, true) then matched[#matched + 1] = it end
    end
    if #matched > 0 then
      local state = items.open[boss.name]
      if state == nil then state = single and boss.name ~= "Trash" end
      local open = filter ~= "" or state
      rows[#rows + 1] = { boss = boss.name, count = #matched, open = open }
      if open then
        for _, it in ipairs(matched) do rows[#rows + 1] = { item = it, boss = boss.name } end
      end
    end
  end
  local reserved = opts.reserved and opts.reserved() or {}
  if #reserved > 0 then
    rows[#rows + 1] = { title = "Reserved now, click one to remove it" }
    for _, entry in ipairs(reserved) do rows[#rows + 1] = { reserved = entry.r, remove = entry.remove } end
  end
  return rows
end

local function Refresh()
  local rows = Rows(strtrim(items.Search:GetText()):lower())
  items.List:SetRows(rows)
  items.Empty:SetShown(#rows == 0)
  if not items.error then items.Status:SetText(opts.status and opts.status() or "") end
end

local function Click(row)
  local d = row.data
  items.error = nil
  if d.count then
    items.open[d.boss] = not d.open
  elseif d.item then
    local ok, reason = true, nil
    if opts.canPick then ok, reason = opts.canPick() end
    if not ok then
      items.error = true
      items.Status:SetText("|cffff6060" .. (reason or "") .. "|r")
      return
    end
    local onPick = opts.onPick
    if not opts.stay then items:Hide() end
    onPick(d.item, d.boss)
  elseif d.remove then
    d.remove()
  end
  if items:IsShown() then Refresh() end
end

local function Enter(row)
  local d = row.data
  local id = (d.item and d.item.id) or (d.reserved and d.reserved.i)
  if not id then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  Raids.ShowItemTooltip(GameTooltip, id)
  if d.item and d.item.chance then GameTooltip:AddLine(("Estimated drop chance: ~%d%%"):format(d.item.chance), 0.6, 0.8, 1) end
  if d.reserved then
    local kind = d.reserved.k == "H" and "Hard reserve" or "Soft reserve"
    GameTooltip:AddLine(("%s for %s, from %s"):format(kind, d.reserved.n, d.reserved.b), 0.6, 0.8, 1)
  end
  GameTooltip:Show()
end

local function InitRow(row, data)
  if not row.Text then
    row:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar", "ADD")
    row.Toggle = row:CreateTexture(nil, "ARTWORK")
    row.Toggle:SetSize(14, 14)
    row.Toggle:SetPoint("LEFT", 4, 0)
    row.Text = UI.CreateCell(row, "GameFontHighlightSmall")
    row.Text:SetPoint("LEFT", 22, 0)
    row.Text:SetPoint("RIGHT", -44, 0)
    row.Right = UI.CreateCell(row, "GameFontDisableSmall", "RIGHT")
    row.Right:SetPoint("RIGHT", -6, 0)
    row:SetScript("OnClick", Click)
    row:SetScript("OnEnter", Enter)
    row:SetScript("OnLeave", GameTooltip_Hide)
  end
  row.data = data
  row.itemID = (data.item and data.item.id) or (data.reserved and data.reserved.i) or nil
  row:GetHighlightTexture():SetAlpha(data.title and 0 or 1)
  row.Toggle:SetShown(data.count ~= nil)
  if data.count then
    row.Toggle:SetTexture(data.open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
    row.Text:SetText("|cffffd100" .. data.boss .. "|r")
    row.Right:SetText(("|cffaaaaaa%d|r"):format(data.count))
  elseif data.title then
    row.Text:SetText("|cffffd100" .. data.title .. "|r")
    row.Right:SetText("")
  elseif data.item then
    row.Text:SetText("   " .. UI.ItemLabel(data.item.id, 16))
    row.Right:SetText(data.item.chance and ("~%d%%"):format(data.item.chance) or "")
  else
    local r = data.reserved
    local info = ZR.RosterInfo(r.n)
    row.Text:SetText(UI.ItemLabel(r.i, 14) .. "  " .. ZR.ColorName(r.n, info and info.classFile))
    row.Right:SetText(data.remove and "|cffff6060remove|r" or "")
  end
end

local function Build()
  items = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  items.open = {}
  items:SetSize(320, 340)
  items:SetFrameStrata("FULLSCREEN_DIALOG")
  items:SetClampedToScreen(true)
  items:EnableMouse(true)
  items:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  items:SetBackdropColor(0.05, 0.05, 0.05, 1)
  items:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  items.Title = UI.Text(items, "GameFontNormal")
  items.Title:SetPoint("TOPLEFT", 12, -10)
  items.Search = CreateFrame("EditBox", nil, items, "SearchBoxTemplate")
  items.Search:SetHeight(20)
  items.Search:SetPoint("TOPLEFT", 16, -28)
  items.Search:SetPoint("TOPRIGHT", -10, -28)
  items.Search:HookScript("OnTextChanged", function()
    items.error = nil
    Refresh()
  end)
  items.Search:SetScript("OnEscapePressed", function() items:Hide() end)
  items.List = UI.CreateTable(items, { { title = "", width = 0 } }, nil, 20, InitRow)
  items.List:SetPoint("TOPLEFT", 8, -54)
  items.List:SetPoint("BOTTOMRIGHT", -8, 26)
  items.List.Header:Hide()
  items.List.ScrollBox:SetPoint("TOPLEFT", items.List, "TOPLEFT", 0, 0)
  items.Empty = UI.Text(items, "GameFontDisableSmall", "No item by that name.")
  items.Empty:SetPoint("CENTER", 0, -10)
  items.Status = UI.Text(items, "GameFontHighlightSmall")
  items.Status:SetPoint("BOTTOMLEFT", 12, 10)
  items.Status:SetPoint("BOTTOMRIGHT", -12, 10)
  items.Status:SetJustifyH("LEFT")
  -- Closes on a click anywhere else, like a normal dropdown.
  items:SetScript("OnUpdate", function(self)
    local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
    if down and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
  end)
  items:SetScript("OnHide", function(self) self.Search:ClearFocus() end)
  items:Hide()
end

-- o: raid, title, onPick(item, boss), optional reserved() -> { { r, remove } }, canPick() -> ok, reason, status(), stay, above.
function UI.ToggleItemPicker(owner, o)
  if not items then Build() end
  if items:IsShown() and items.owner == owner then
    items:Hide()
    return
  end
  opts = o
  Raids.PreloadLoot(o.raid)
  -- Folds start closed for each raid.
  if items.raid ~= o.raid then
    items.open = {}
    items.raid = o.raid
  end
  items.owner = owner
  items.error = nil
  items.Title:SetText(o.title or "")
  items:ClearAllPoints()
  if o.above then
    items:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
  else
    items:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  end
  items.Search:SetText("")
  items:Show()
  Refresh()
  items.Search:SetFocus()
end

function UI.RefreshItemPicker()
  if items and items:IsShown() then Refresh() end
end

-- owner limits it to a picker opened from that button.
function UI.HideItemPicker(owner)
  if items and (not owner or items.owner == owner) then items:Hide() end
end
