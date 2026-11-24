local _, JGH = ...
local UI = JGH.UI

-- Our page in Guild Settings, picked from the Guild Control dropdown like Blizzard's own pages.
local TAB = "JemiGuildHelper"
local ROW_HEIGHT = 22
local BLIZZARD_PAGES = { "orderFrame", "rankPermFrame", "bankTabFrame", "discordFrame" }

local page
local rows = {}
local discordError

local function MemberCount(order)
  local n = GetNumMembersInRank and GetNumMembersInRank(order)
  if type(n) ~= "number" or JGH.IsSecret(n) then return "" end
  return n == 1 and "1 member" or n .. " members"
end

-- A section's tinted box, like the ones on Blizzard's Rank Permissions page.
local function Box(y, height)
  local box = CreateFrame("Frame", nil, page)
  box:SetPoint("TOP", 0, y)
  box:SetSize(290, height or 1)
  local bg = box:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.95, 0.95, 1, 0.09)
  return box
end

local function RefreshDiscord()
  local link, canEdit = JGH.Discord.Link(), JGH.Discord.CanEdit()
  local input = page.Input
  if not input:HasFocus() then input:SetText(link or "") end
  input:SetEnabled(canEdit)
  input:SetTextColor((canEdit and HIGHLIGHT_FONT_COLOR or GRAY_FONT_COLOR):GetRGB())
  local typed = strtrim(input:GetText())
  page.Save:SetEnabled(canEdit and typed ~= (link or ""))

  local status, color = discordError, RED_FONT_COLOR
  if not status then
    color = GRAY_FONT_COLOR
    if not canEdit then
      status = "Your rank can't edit Guild Info."
    elseif link then
      status = "Saved in Guild Info for everyone."
    else
      status = "No link yet, so Join Discord is hidden."
    end
  end
  page.Status:SetText(status)
  page.Status:SetTextColor(color:GetRGB())
end

local function RefreshRanks()
  local gm = IsGuildLeader()
  local n = JGH.Ranks.Count()
  for i = 1, n do
    local row = rows[i]
    row.Label:SetText((RANK or "Rank") .. " " .. i .. ":")
    row.Name:SetText(JGH.Ranks.Name(i))
    row.Count:SetText(MemberCount(i))
    row.Check:SetChecked(JGH.Ranks.CanRecruit(i))
    row.Check:SetEnabled(i > 1 and gm)
    row:Show()
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  page.List:SetHeight(math.max(n, 1) * ROW_HEIGHT + 8)
  page.Reset:SetShown(gm)
  page.Reset:SetEnabled(not JGH.Ranks.IsDefault())
end

local function Refresh()
  if not page or not page:IsShown() then return end
  RefreshDiscord()
  RefreshRanks()
end

local function SaveDiscord()
  local typed = strtrim(page.Input:GetText())
  local link = typed ~= "" and JGH.Discord.Parse(typed) or nil
  if typed ~= "" and not link then
    discordError = "Not a Discord invite, like discord.gg/abc."
  else
    local ok, err = JGH.Discord.Save(link)
    discordError = not ok and err or nil
    if ok then
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
      page.Input:ClearFocus()
    end
  end
  Refresh()
end

local function CheckTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip_SetTitle(GameTooltip, JGH.Ranks.Name(self.order))
  if self.order == 1 then
    GameTooltip_AddNormalLine(GameTooltip, "The Guild Master can always use Recruitment.")
  else
    GameTooltip_AddNormalLine(GameTooltip, "Can open the Recruitment tab in Jemi Guild Helper.")
    if not IsGuildLeader() then GameTooltip_AddNormalLine(GameTooltip, "Only the Guild Master can change this.") end
  end
  GameTooltip:Show()
end

local function CreateRow(i)
  local row = CreateFrame("Frame", nil, page.List)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 6, -4 - (i - 1) * ROW_HEIGHT)
  row:SetPoint("RIGHT", -6, 0)

  -- Same look as Blizzard's permission boxes, without their click handler.
  local check = CreateFrame("CheckButton", nil, row)
  check:SetSize(20, 20)
  check:SetPoint("LEFT")
  check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  check:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
  check:SetMotionScriptsWhileDisabled(true)
  -- Clicking the rank name ticks the box too.
  check:SetHitRectInsets(0, -180, 0, 0)
  check.order = i
  check:SetScript("OnClick", function(self)
    PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    JGH.Ranks.Set(self.order, self:GetChecked())
  end)
  check:SetScript("OnEnter", CheckTooltip)
  check:SetScript("OnLeave", GameTooltip_Hide)
  row.Check = check

  row.Label = UI.Text(row, "GameFontNormal")
  row.Label:SetPoint("LEFT", check, "RIGHT", 6, 0)
  row.Name = UI.Text(row, "GameFontHighlight")
  row.Name:SetPoint("LEFT", 92, 0)
  row.Count = UI.Text(row, "GameFontDisableSmall")
  row.Count:SetPoint("RIGHT", -4, 0)
  return row
end

local function BuildDiscord()
  local title = UI.Text(page, "GameFontNormal", "Discord invite")
  title:SetPoint("TOPLEFT", 12, -12)

  local box = Box(-30, 54)
  page.Save = UI.CreateButton(box, SAVE or "Save", 64, 22)
  page.Save:SetPoint("TOPRIGHT", -6, -6)
  page.Save:SetScript("OnClick", SaveDiscord)

  page.Input = UI.CreateInput(box, 1, 22)
  page.Input:SetPoint("TOPLEFT", 14, -6)
  page.Input:SetPoint("RIGHT", page.Save, "LEFT", -8, 0)
  page.Input:SetMaxLetters(120)
  page.Input:SetScript("OnEnterPressed", SaveDiscord)
  page.Input:SetScript("OnEscapePressed", function(self)
    discordError = nil
    self:ClearFocus()
    self:SetText(JGH.Discord.Link() or "")
    Refresh()
  end)
  page.Input:SetScript("OnTextChanged", function(_, userInput)
    if not userInput then return end
    discordError = nil
    Refresh()
  end)
  page.Input:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, "Discord invite")
    GameTooltip_AddNormalLine(GameTooltip, "Paste an invite that never expires. Clear it and save to remove the button.")
    GameTooltip:Show()
  end)
  page.Input:SetScript("OnLeave", GameTooltip_Hide)

  page.Status = UI.Text(box, "GameFontDisableSmall")
  page.Status:SetPoint("BOTTOMLEFT", 8, 7)
  page.Status:SetPoint("RIGHT", -8, 0)
  page.Status:SetJustifyH("LEFT")
end

local function BuildRanks()
  local title = UI.Text(page, "GameFontNormal", "Recruitment tab")
  title:SetPoint("TOPLEFT", 12, -96)

  page.Reset = UI.CreateButton(page, "Reset", 70, 20)
  page.Reset:SetPoint("TOPRIGHT", -10, -92)
  page.Reset:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    JGH.Ranks.Reset()
  end)
  UI.SetButtonTooltip(page.Reset, function() return "Reset to Default", "Only the top two ranks can recruit." end)

  local desc = UI.Text(page, "GameFontHighlightSmall",
    "Ticked ranks can open Recruitment. Members get changes while the Guild Master is online.")
  desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  desc:SetPoint("RIGHT", -12, 0)
  desc:SetJustifyH("LEFT")

  page.List = Box(-142)
  for i = 1, 10 do rows[i] = CreateRow(i) end
end

local function Build()
  if page or not GuildControlUI then return end
  page = CreateFrame("Frame", nil, GuildControlUI)
  page:SetPoint("TOPLEFT", _G.GuildControlUIHbar or GuildControlUI, "BOTTOMLEFT", 5, -3)
  page:SetPoint("BOTTOMRIGHT", -12, 12)
  page:Hide()
  BuildDiscord()
  BuildRanks()

  page:SetScript("OnShow", function()
    discordError = nil
    Refresh()
  end)
  for _, key in ipairs(BLIZZARD_PAGES) do
    local f = GuildControlUI[key]
    if f then f:HookScript("OnShow", function() page:Hide() end) end
  end
end

local function ShowPage()
  for _, key in ipairs(BLIZZARD_PAGES) do
    local f = GuildControlUI[key]
    if f then f:Hide() end
  end
  StaticPopup_Hide("CONFIRM_RANK_AUTHENTICATOR_REMOVE")
  GuildControlUI.selectedTab = TAB
  page:Show()
end

local function IsSelected()
  return GuildControlUI.selectedTab == TAB
end

-- Opens Guild Settings straight on our page, for the Edit Discord Link button.
function UI.OpenGuildControlPage()
  if not JGH.IsOfficer() then return end
  if InCombatLockdown() then
    UIErrorsFrame:AddExternalErrorMessage(ERR_NOT_IN_COMBAT)
    return
  end
  if not GuildControlUI and C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_GuildControlUI") end
  Build()
  if not page then return end
  if not GuildControlUI:IsShown() then ShowUIPanel(GuildControlUI) end
  ShowPage()
  GuildControlUI.dropdown:GenerateMenu()
  if not JGH.Discord.Link() and JGH.Discord.CanEdit() then page.Input:SetFocus() end
end

function UI.InitGuildControl()
  if not (Menu and Menu.ModifyMenu) then return end
  Menu.ModifyMenu("MENU_GUILD_PERMISSIONS", function(_, root)
    if not JGH.IsOfficer() then return end
    Build()
    if not page then return end
    -- Officers may have no Blizzard pages above ours.
    if IsGuildLeader() or (C_Discord and C_Discord.IsEnabled and C_Discord.IsEnabled()) then root:CreateDivider() end
    root:CreateRadio(("|T%s:16:16|t %s"):format(JGH.ICON_TEXTURE, JGH.TITLE), IsSelected, ShowPage)
  end)
  JGH.On("RankAccessChanged", Refresh)
  JGH.On("RosterChanged", Refresh)
  JGH.On("DiscordChanged", Refresh)
end
