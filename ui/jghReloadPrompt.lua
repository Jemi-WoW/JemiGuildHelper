local _, JGH = ...
local UI = JGH.UI

-- Shown when old ZUGZUG Reborn code ran this session; only a reload closes it.
local shade

local function Build()
  -- Dims the screen and swallows clicks so the window can't be missed or skipped.
  shade = CreateFrame("Frame", nil, UIParent)
  shade:SetAllPoints()
  shade:SetFrameStrata("FULLSCREEN_DIALOG")
  shade:EnableMouse(true)
  local dim = shade:CreateTexture(nil, "BACKGROUND")
  dim:SetAllPoints()
  dim:SetColorTexture(0, 0, 0, 0.6)

  local f = CreateFrame("Frame", "JemiGuildHelperReloadPrompt", shade, "ButtonFrameTemplate")
  f:SetSize(440, 236)
  f:SetPoint("CENTER", 0, 60)
  f:SetFrameLevel(shade:GetFrameLevel() + 10)
  f:SetTitle(JGH.TITLE)
  f:SetPortraitToAsset(JGH.ICON_TEXTURE)
  if f.CloseButton then f.CloseButton:Hide() end

  local head = UI.Text(f.Inset, "GameFontNormalLarge", "ZUGZUG Reborn is now Jemi Guild Helper")
  head:SetPoint("TOPLEFT", 16, -18)
  head:SetPoint("TOPRIGHT", -16, -18)

  local body = UI.Text(f.Inset, "GameFontHighlight",
    "Your settings have been moved over.\n\n"
    .. "Reload your interface to finish. After that, the old addon is gone for good.")
  body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -14)
  body:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -14)
  body:SetSpacing(2)

  local reload = UI.CreateButton(f, "Reload UI", 180, 22)
  reload:SetPoint("BOTTOM", 0, 4)
  reload:SetScript("OnClick", function() ReloadUI() end)
end

function UI.ShowReloadPrompt()
  if not shade then Build() end
  shade:Show()
  PlaySound(SOUNDKIT.RAID_WARNING)
  if FlashClientIcon then FlashClientIcon() end
end
