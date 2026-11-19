local _, ZR = ...
local UI = ZR.UI
local Loot = ZR.Loot

-- Next to the loot window for whoever runs the raid: each item, its reserves, a roll length and a button to roll it off.
local MIN_QUALITY = 3
local ROW = 40
local WIDTH = 400

local panel

local function ReserveText(mode, names)
  if mode == "H" then return ("|cffff8040Hard reserve|r  %s"):format(table.concat(names, ", ")) end
  if mode == "S" then return ("|cff40ff40Soft reserve|r  %s"):format(table.concat(names, ", ")) end
  return "|cffaaaaaaFree roll|r"
end

local function SetupDuration(dd, row)
  dd:SetupMenu(function(_, root)
    for _, secs in ipairs(Loot.DURATIONS) do
      root:CreateRadio(secs .. "s", function() return row.dur == secs end, function()
        row.dur = secs
        ZR.DB().rollTime = secs
      end)
    end
  end)
end

local function RowFrame(i)
  local r = panel.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, panel)
  r:SetHeight(ROW)
  r:SetPoint("TOPLEFT", 12, -50 - (i - 1) * (ROW + 4))
  r:SetPoint("RIGHT", -12, 0)
  r.Bg = r:CreateTexture(nil, "BACKGROUND")
  r.Bg:SetAllPoints()
  r.Bg:SetColorTexture(1, 1, 1, 0.04)
  r:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar", "ADD")
  r.Icon = r:CreateTexture(nil, "ARTWORK")
  r.Icon:SetSize(32, 32)
  r.Icon:SetPoint("LEFT", 4, 0)
  r.IconBorder = r:CreateTexture(nil, "OVERLAY")
  r.IconBorder:SetSize(38, 38)
  r.IconBorder:SetPoint("CENTER", r.Icon, "CENTER", 0, -1)
  r.Button = UI.CreateButton(r, "Roll", 80, 22)
  r.Button:SetPoint("RIGHT", -4, 0)
  r.Button:SetScript("OnClick", function(self)
    local row = self:GetParent()
    Loot.Start(row.link, row.dur)
  end)
  r.Duration = CreateFrame("DropdownButton", nil, r, "WowStyle1DropdownTemplate")
  r.Duration:SetWidth(64)
  r.Duration:SetPoint("RIGHT", r.Button, "LEFT", -6, 0)
  SetupDuration(r.Duration, r)
  r.Name = UI.CreateCell(r, "GameFontNormal")
  r.Name:SetPoint("TOPLEFT", r.Icon, "TOPRIGHT", 8, -2)
  r.Name:SetPoint("RIGHT", r.Duration, "LEFT", -8, 0)
  r.Reserve = UI.CreateCell(r, "GameFontHighlightSmall")
  r.Reserve:SetPoint("BOTTOMLEFT", r.Icon, "BOTTOMRIGHT", 8, 2)
  r.Reserve:SetPoint("RIGHT", r.Duration, "LEFT", -8, 0)
  r:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetHyperlink(self.link)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  panel.rows[i] = r
  return r
end

local function Items()
  local out = {}
  for slot = 1, GetNumLootItems() do
    local texture, _, _, _, quality, _, _, _, _, isCoin = GetLootSlotInfo(slot)
    local link = GetLootSlotLink(slot)
    if link and not isCoin and (Loot.test or (quality or 0) >= MIN_QUALITY) then
      out[#out + 1] = { link = link, icon = texture, quality = quality, itemID = tonumber(link:match("item:(%d+)")) }
    end
  end
  return out
end

local function Refresh()
  if not panel or not panel:IsShown() then return end
  local running = Loot.session and not Loot.session.ended
  for i, it in ipairs(panel.items) do
    local r = RowFrame(i)
    r.link = it.link
    r.dur = r.dur or Loot.Duration()
    r.Icon:SetTexture(it.icon)
    local atlas = ColorManager and ColorManager.GetAtlasDataForLootBorderItemQuality
      and ColorManager.GetAtlasDataForLootBorderItemQuality(it.quality or 1)
    r.IconBorder:SetShown(atlas ~= nil)
    if atlas then r.IconBorder:SetAtlas(atlas) end
    r.Name:SetText(it.link)
    local mode, names = Loot.ReservesFor(it.itemID)
    r.Reserve:SetText(ReserveText(mode, names))
    -- A hard reserve needs no roll or timer, only telling the raid who gets it.
    r.Button:SetText(mode == "H" and "Announce" or "Roll")
    r.Button:SetEnabled(not running)
    r.Duration:SetShown(mode ~= "H")
    r.Duration:GenerateMenu()
    r:Show()
  end
  for i = #panel.items + 1, #panel.rows do panel.rows[i]:Hide() end
  local ev = Loot.CurrentRaid()
  panel.Source:SetText(ev and ("Reserves from |cffffffff%s|r"):format(ZR.Raids.Title(ev)) or "Not inside a planned raid, so every item is a free roll")
  panel:SetHeight(62 + #panel.items * (ROW + 4))
end

local function Build()
  panel = CreateFrame("Frame", "ZUGZUGRebornLootPanel", UIParent, "DefaultPanelFlatTemplate")
  panel:SetSize(WIDTH, 120)
  panel:SetFrameStrata("HIGH")
  panel:SetClampedToScreen(true)
  panel:EnableMouse(true)
  panel:SetMovable(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:SetTitle(ZR.TITLE .. " loot")
  panel.Close = CreateFrame("Button", nil, panel, "UIPanelCloseButtonDefaultAnchors")
  panel.Close:SetScript("OnClick", function() panel:Hide() end)
  panel.Source = UI.Text(panel, "GameFontHighlightSmall")
  panel.Source:SetPoint("TOPLEFT", 14, -30)
  panel.rows = {}
  panel:Hide()
end

local function Place()
  panel:ClearAllPoints()
  if LootFrame and LootFrame:IsShown() then
    panel:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 6, 0)
  else
    panel:SetPoint("LEFT", UIParent, "CENTER", 120, 0)
  end
end

-- Read at once: autoloot can empty the loot window within the same frame.
local function Open()
  if not Loot.CanLead() or not Loot.CurrentRaid() then return end
  local items = Items()
  if #items == 0 then return end
  if not panel then Build() end
  panel.items = items
  Place()
  panel:Show()
  Refresh()
  C_Timer.After(0, Place)
end

-- The list stays after looting, autoloot included, until closed or the next loot opens.
ZR.RegisterEvent("LOOT_READY", Open)
ZR.RegisterEvent("LOOT_OPENED", Open)
ZR.RegisterEvent("PLAYER_ENTERING_WORLD", function()
  if panel and panel:IsShown() and not Loot.CurrentRaid() then panel:Hide() end
end)
ZR.On("LootStart", Refresh)
ZR.On("LootEnd", Refresh)
ZR.On("RaidsChanged", Refresh)
