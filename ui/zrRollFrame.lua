local _, ZR = ...
local UI = ZR.UI
local Loot = ZR.Loot

-- The roll window: a standard game window with the item as its portrait and everyone's rolls below.
local DICE = "Interface\\Buttons\\UI-GroupLoot-Dice-Up"
local COIN = "Interface\\Buttons\\UI-GroupLoot-Coin-Up"
local PASS_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local f

local function ItemColor(id)
  local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 4]
  return c or { r = 0.64, g = 0.21, b = 0.93 }
end

local function SavePosition()
  local point, _, _, x, y = f:GetPoint()
  ZR.DB().rollPos = { point, x, y }
end

local function Icon(path)
  return ("|T%s:18:18|t "):format(path)
end

local function RollButton(text, icon, width, onClick)
  local b = UI.CreateButton(f, Icon(icon) .. text, width, 26)
  b:SetScript("OnClick", onClick)
  UI.SetButtonTooltip(b, function(self) return self.tip, self.why end)
  return b
end

local function SetButton(b, enabled, why)
  b:SetEnabled(enabled)
  b.why = why
end

local function TypeText(s, r)
  if r.again then return "|cff888888rolled again|r" end
  if not r.kind then return ("|cff888888%s, not valid|r"):format(r.range) end
  if not r.allowed then return "|cff888888not reserved|r" end
  local tag = r.kind == "MS" and "|cffffd100Main spec|r" or "|cffaaaaaaOff spec|r"
  if s.mode == "S" then tag = tag .. "  |cff40ff40SR|r" end
  return tag
end

local function InitRow(row, data)
  if not row.Name then
    UI.StyleRow(row)
    row.Rank = UI.CreateCell(row, "GameFontDisableSmall", "RIGHT")
    row.Rank:SetPoint("LEFT", 2, 0)
    row.Rank:SetWidth(16)
    row.Name = UI.CreateCell(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", row.Rank, "RIGHT", 8, 0)
    row.Name:SetWidth(118)
    row.Roll = UI.CreateCell(row, "GameFontNormal", "RIGHT")
    row.Roll:SetPoint("LEFT", 150, 0)
    row.Roll:SetWidth(34)
    row.Type = UI.CreateCell(row, "GameFontHighlightSmall")
    row.Type:SetPoint("LEFT", row.Roll, "RIGHT", 14, 0)
    row.Type:SetPoint("RIGHT", -4, 0)
  end
  local r, s = data.r, Loot.session
  row.Rank:SetText(r.valid and data.rank or "")
  row.Name:SetText(ZR.ColorName(r.name, r.class))
  row.Roll:SetText(r.valid and r.roll or ("|cff888888" .. r.roll .. "|r"))
  row.Type:SetText(s and TypeText(s, r) or "")
end

local function Refresh()
  local s = Loot.session
  if not f or not s then return end
  local list, winner, tie = Loot.Ranked(s)
  local rows = {}
  for i, r in ipairs(list) do rows[#rows + 1] = { r = r, rank = i } end
  f.List:SetRows(rows)
  f.Empty:SetShown(#list == 0)
  f.Empty:SetText(s.mode == "H" and "No roll needed, it's hard reserved." or "No rolls yet.")

  local me = ZR.PlayerName()
  local mine
  for _, r in ipairs(s.rolls) do
    if r.name == me and not mine then mine = r end
  end
  local can = Loot.CanRoll(s) and not mine
  local why = (s.ended and "The roll is over.") or (mine and "You already rolled.")
    or (s.mode == "S" and ("Soft reserved by %s. Only they roll."):format(table.concat(s.names, ", "))) or nil
  SetButton(f.Main, can, why)
  SetButton(f.Off, can, why)
  local rolling = s.mode ~= "H"
  f.Main:SetShown(rolling)
  f.Off:SetShown(rolling)
  f.Pass:SetShown(rolling and not Loot.IsLeader(s))

  if s.mode == "H" then
    f.Reserve:SetText(("|cffff8040Hard reserve|r for |cffffffff%s|r"):format(table.concat(s.names, ", ")))
  elseif s.mode == "S" then
    f.Reserve:SetText(("|cff40ff40Soft reserve|r: only |cffffffff%s|r may roll"):format(table.concat(s.names, ", ")))
  else
    f.Reserve:SetText("Free roll: main spec beats off spec")
  end
  f.Mine:SetText(mine and ("You rolled |cffffffff%d|r%s"):format(mine.roll, mine.valid and "" or ", it doesn't count") or "")

  if not s.ended then
    f.Result:SetText("")
  elseif winner and tie then
    f.Result:SetText("|cffff8040Tie! They roll again.|r")
  elseif winner then
    f.Result:SetText(("Winner: %s |cffffffff%d|r"):format(ZR.ColorName(winner.name, winner.class), winner.roll))
  elseif s.mode == "H" then
    f.Result:SetText(("Goes to |cffffffff%s|r"):format(table.concat(s.names, ", ")))
  else
    f.Result:SetText("Nobody rolled.")
  end
  local leader = Loot.IsLeader(s)
  f.StopButton:SetShown(leader and not s.ended)
  f.AnnounceButton:SetShown(leader and s.ended and s.mode ~= "H")
end

local function OnUpdate(self)
  local s = Loot.session
  if not s or s.ended or s.mode == "H" then
    self.Timer:SetValue(0)
    self.TimerText:SetText(s and s.mode ~= "H" and "Rolls closed" or "")
    return
  end
  local left = math.max(0, s.endAt - GetTime())
  self.Timer:SetValue(left)
  self.TimerText:SetText(("%d seconds left"):format(math.ceil(left)))
end

local function Build()
  f = CreateFrame("Frame", "ZUGZUGRebornRollFrame", UIParent, "ButtonFrameTemplate")
  f:SetSize(360, 372)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)
  f:SetTitle("Loot roll")
  local pos = ZR.DB().rollPos
  if pos and pos[1] then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end

  -- The portrait shows the item; hovering it gives the item tooltip.
  f.ItemHit = CreateFrame("Button", nil, f)
  f.ItemHit:SetSize(56, 56)
  f.ItemHit:SetPoint("TOPLEFT", -4, 6)
  f.ItemHit:SetFrameLevel(f:GetFrameLevel() + 10)
  f.ItemHit:SetScript("OnEnter", function(self)
    local s = Loot.session
    if not s then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    ZR.Raids.ShowItemTooltip(GameTooltip, s.itemID)
    GameTooltip:Show()
  end)
  f.ItemHit:SetScript("OnLeave", GameTooltip_Hide)

  f.ItemName = UI.Text(f, "GameFontNormalLarge")
  f.ItemName:SetPoint("TOPLEFT", 64, -30)
  f.ItemName:SetPoint("RIGHT", -12, 0)
  f.ItemName:SetJustifyH("LEFT")
  f.ItemName:SetWordWrap(false)
  f.Reserve = UI.Text(f, "GameFontHighlightSmall")
  f.Reserve:SetPoint("TOPLEFT", f.ItemName, "BOTTOMLEFT", 0, -4)
  f.Reserve:SetPoint("RIGHT", -12, 0)
  f.Reserve:SetJustifyH("LEFT")
  f.Reserve:SetWordWrap(false)

  f.Timer = CreateFrame("StatusBar", nil, f)
  f.Timer:SetHeight(14)
  f.Timer:SetPoint("TOPLEFT", 16, -72)
  f.Timer:SetPoint("TOPRIGHT", -16, -72)
  f.Timer:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
  f.Timer:SetStatusBarColor(1, 0.82, 0)
  local timerBg = f.Timer:CreateTexture(nil, "BACKGROUND")
  timerBg:SetAllPoints()
  timerBg:SetColorTexture(0, 0, 0, 0.7)
  local timerBorder = CreateFrame("Frame", nil, f.Timer, "BackdropTemplate")
  timerBorder:SetPoint("TOPLEFT", -3, 3)
  timerBorder:SetPoint("BOTTOMRIGHT", 3, -3)
  timerBorder:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
  timerBorder:SetBackdropBorderColor(0.6, 0.6, 0.6)
  f.TimerText = UI.Text(f.Timer, "GameFontHighlightSmall")
  f.TimerText:SetPoint("CENTER")

  f.Main = RollButton("Main spec", DICE, 110, function() RandomRoll(1, 100) end)
  f.Main.tip = "Main spec roll (1-100)"
  f.Main:SetPoint("TOPLEFT", 14, -96)
  f.Off = RollButton("Off spec", COIN, 104, function() RandomRoll(1, 99) end)
  f.Off.tip = "Off spec roll (1-99)"
  f.Off:SetPoint("LEFT", f.Main, "RIGHT", 6, 0)
  f.Pass = RollButton(PASS or "Pass", PASS_ICON, 94, function() f:Hide() end)
  f.Pass.tip = "Close this without rolling"
  f.Pass:SetPoint("LEFT", f.Off, "RIGHT", 6, 0)
  f.Mine = UI.Text(f, "GameFontHighlightSmall")
  f.Mine:SetPoint("TOPLEFT", f.Main, "BOTTOMLEFT", 2, -6)

  f.Inset:ClearAllPoints()
  f.Inset:SetPoint("TOPLEFT", 6, -146)
  f.Inset:SetPoint("BOTTOMRIGHT", -8, 36)
  f.List = UI.CreateTable(f.Inset, {
    { title = "Player", width = 150 },
    { title = "Roll", width = 50 },
    { title = "Type", width = 0 },
  }, nil, 20, InitRow)
  f.List:SetPoint("TOPLEFT", 4, -4)
  f.List:SetPoint("BOTTOMRIGHT", -4, 4)
  f.Empty = UI.Text(f.Inset, "GameFontDisable")
  f.Empty:SetPoint("CENTER", 0, -8)

  f.Result = UI.Text(f, "GameFontNormal")
  f.Result:SetPoint("BOTTOMLEFT", 14, 11)
  f.Result:SetPoint("RIGHT", -140, 0)
  f.Result:SetJustifyH("LEFT")
  f.Result:SetWordWrap(false)
  f.StopButton = UI.CreateButton(f, "End roll", 110, 22)
  f.StopButton:SetPoint("BOTTOMRIGHT", -8, 6)
  f.StopButton:SetScript("OnClick", Loot.Stop)
  f.AnnounceButton = UI.CreateButton(f, "Announce winner", 130, 22)
  f.AnnounceButton:SetPoint("BOTTOMRIGHT", -8, 6)
  f.AnnounceButton:SetScript("OnClick", Loot.AnnounceWinner)

  f:SetScript("OnUpdate", OnUpdate)
  f:Hide()
end

local function Show(s)
  if not f then Build() end
  local color = ItemColor(s.itemID)
  f:SetPortraitToAsset(ZR.Raids.ItemIcon(s.itemID))
  f.ItemName:SetText(ZR.Raids.ItemName(s.itemID))
  f.ItemName:SetTextColor(color.r, color.g, color.b)
  f.Timer:SetMinMaxValues(0, math.max(s.dur, 1))
  f.Timer:SetShown(s.mode ~= "H")
  f:Show()
  Refresh()
  PlaySound(SOUNDKIT.RAID_WARNING or 8959)
end

ZR.On("LootStart", Show)
ZR.On("LootRoll", Refresh)
ZR.On("LootEnd", Refresh)
-- Item names can arrive after the window opened.
ZR.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, id)
  local s = Loot.session
  if f and f:IsShown() and s and s.itemID == id then f.ItemName:SetText(ZR.Raids.ItemName(id)) end
end)
