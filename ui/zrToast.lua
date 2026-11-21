local _, ZR = ...
local UI = ZR.UI

-- Toasts in the guild challenge alert's art, so they match the game's own.
local ART = "Interface\\GuildFrame\\GuildChallenges"
local GLOW = "Interface\\AchievementFrame\\UI-Achievement-Alert-Glow"
local WIDTH, HEIGHT = 270, 67
local MAX_SHOWN = 3
local STAY = 10
local FADE = 1.5
local GAP = 4

local pool, shown, waiting = {}, {}, {}
local anchor

local function SavePosition()
  local point, _, _, x, y = anchor:GetPoint()
  ZR.DB().toastPos = { point, x, y }
end

local function PlaceAnchor()
  anchor:ClearAllPoints()
  local pos = ZR.DB().toastPos
  if pos then
    anchor:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
  else
    anchor:SetPoint("TOP", UIParent, "TOP", 0, -190)
  end
end

local function Anchor()
  if anchor then return anchor end
  anchor = CreateFrame("Frame", "ZUGZUGRebornToastAnchor", UIParent)
  anchor:SetSize(WIDTH, HEIGHT)
  anchor:SetMovable(true)
  anchor:SetClampedToScreen(true)
  PlaceAnchor()
  return anchor
end

function UI.ResetToastPosition()
  ZR.DB().toastPos = nil
  if anchor then PlaceAnchor() end
end

local function Layout()
  local prev
  for _, t in ipairs(shown) do
    t:ClearAllPoints()
    if prev then
      t:SetPoint("TOP", prev, "BOTTOM", 0, -GAP)
    else
      t:SetPoint("TOP", Anchor(), "TOP")
    end
    prev = t
  end
end

local function Release(t)
  for i, other in ipairs(shown) do
    if other == t then table.remove(shown, i) break end
  end
  t.Out:Stop()
  t:Hide()
  pool[#pool + 1] = t
  Layout()
  if waiting[1] then UI.Toast(table.remove(waiting, 1)) end
end

local function Fade(t, delay)
  t.Out:Stop()
  t.OutAlpha:SetStartDelay(delay)
  t.Out:Play()
end

local function Tex(t, layer, file, w, h, l, r, top, b)
  local tex = t:CreateTexture(nil, layer)
  tex:SetTexture(file)
  tex:SetSize(w, h)
  tex:SetTexCoord(l, r, top, b)
  return tex
end

local function Flash(tex, build)
  local g = tex:CreateAnimationGroup()
  build(g)
  g:SetScript("OnFinished", function() tex:Hide() end)
  return g
end

local function CreateToast()
  local t = CreateFrame("Button", nil, UIParent)
  t:SetSize(WIDTH, HEIGHT)
  t:SetFrameStrata("DIALOG")
  t:RegisterForClicks("RightButtonUp")
  t:RegisterForDrag("LeftButton")
  t.EmblemBackground = Tex(t, "BACKGROUND", ART, 37, 36, 0.06054688, 0.13281250, 0.00390625, 0.14453125)
  t.EmblemBackground:SetPoint("LEFT", 14, 0)
  t.Banner = Tex(t, "BORDER", ART, WIDTH, HEIGHT, 0.13671875, 0.66406250, 0.00390625, 0.26562500)
  t.Banner:SetPoint("LEFT")
  t.EmblemBorder = Tex(t, "BORDER", ART, 37, 36, 0.06054688, 0.13281250, 0.15234375, 0.29296875)
  t.EmblemBorder:SetPoint("LEFT", 14, 0)
  t.EmblemIcon = t:CreateTexture(nil, "ARTWORK")
  t.EmblemIcon:SetSize(31, 35)
  t.EmblemIcon:SetPoint("CENTER", t, "LEFT", 32, 0)
  t.IconBg = t:CreateTexture(nil, "ARTWORK", nil, -1)
  t.IconBg:SetColorTexture(0, 0, 0, 1)
  t.IconBg:SetAllPoints(t.EmblemBackground)
  t.Icon = t:CreateTexture(nil, "ARTWORK")
  t.Icon:SetAllPoints(t.EmblemBackground)
  t.Title = UI.Text(t, "GameFontNormal")
  t.Title:SetPoint("LEFT", 66, 9)
  t.Title:SetWidth(132)
  t.Title:SetJustifyH("LEFT")
  t.Title:SetWordWrap(false)
  t.Text = UI.Text(t, "GameFontHighlightSmall")
  t.Text:SetPoint("LEFT", 66, -9)
  t.Text:SetWidth(132)
  t.Text:SetJustifyH("LEFT")
  t.Text:SetWordWrap(false)
  t.Button = UI.CreateButton(t, "", 58, 20)
  t.Button:SetPoint("RIGHT", -16, 1)

  t.Glow = Tex(t, "OVERLAY", GLOW, 350, 151, 0, 0.78125, 0, 0.66796875)
  t.Glow:SetPoint("CENTER")
  t.Glow:SetBlendMode("ADD")
  t.GlowIn = Flash(t.Glow, function(g)
    local a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(0) a:SetToAlpha(1) a:SetDuration(0.2) a:SetOrder(1)
    local b = g:CreateAnimation("Alpha")
    b:SetFromAlpha(1) b:SetToAlpha(0) b:SetDuration(0.5) b:SetOrder(2)
  end)
  t.Shine = Tex(t, "OVERLAY", GLOW, 67, 60, 0.78125, 0.912109375, 0, 0.28125)
  t.Shine:SetPoint("BOTTOMLEFT", 0, 4)
  t.Shine:SetBlendMode("ADD")
  t.ShineIn = Flash(t.Shine, function(g)
    local a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(0) a:SetToAlpha(1) a:SetDuration(0.2) a:SetOrder(1)
    local m = g:CreateAnimation("Translation")
    m:SetOffset(200, 0) m:SetDuration(0.71) m:SetOrder(2)
    local b = g:CreateAnimation("Alpha")
    b:SetFromAlpha(1) b:SetToAlpha(0) b:SetStartDelay(0.35) b:SetDuration(0.5) b:SetOrder(2)
  end)

  t.Out = t:CreateAnimationGroup()
  t.OutAlpha = t.Out:CreateAnimation("Alpha")
  t.OutAlpha:SetFromAlpha(1)
  t.OutAlpha:SetToAlpha(0)
  t.OutAlpha:SetDuration(FADE)
  t.Out:SetScript("OnFinished", function() Release(t) end)

  t:SetScript("OnClick", Release)
  t:SetScript("OnHide", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
  t:SetScript("OnDragStart", function() Anchor():StartMoving() end)
  t:SetScript("OnDragStop", function()
    Anchor():StopMovingOrSizing()
    SavePosition()
  end)
  -- Hovering keeps it up, so the button can still be reached.
  t:SetScript("OnEnter", function(self)
    self.Out:Stop()
    self:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Drag to move, right-click to close.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  t:SetScript("OnLeave", function(self)
    GameTooltip_Hide()
    Fade(self, 3)
  end)
  t.Button:HookScript("OnEnter", function() t.Out:Stop() t:SetAlpha(1) end)
  t.Button:HookScript("OnLeave", function() if not t:IsMouseOver() then Fade(t, 3) end end)
  return t
end

local function SetEmblem(t, icon, atlas)
  t.EmblemBackground:SetTexture(ART)
  t.EmblemBackground:SetTexCoord(0.06054688, 0.13281250, 0.00390625, 0.14453125)
  t.EmblemBackground:SetVertexColor(1, 1, 1)
  t.EmblemBorder:SetTexture(ART)
  t.EmblemBorder:SetTexCoord(0.06054688, 0.13281250, 0.15234375, 0.29296875)
  t.EmblemBorder:SetVertexColor(1, 1, 1)
  t.EmblemIcon:SetTexture(nil)
  local custom = icon ~= nil or atlas ~= nil
  -- The tabard ring is white until tinted with guild colours, so a custom icon fills its space instead.
  t.EmblemBackground:SetShown(not custom)
  t.EmblemBorder:SetShown(not custom)
  t.Icon:SetShown(custom)
  t.IconBg:SetShown(custom)
  if atlas then
    t.Icon:SetAtlas(atlas)
  elseif icon then
    t.Icon:SetTexture(icon)
    t.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  elseif SetLargeGuildTabardTextures then
    pcall(SetLargeGuildTabardTextures, "player", t.EmblemIcon, t.EmblemBackground, t.EmblemBorder)
  end
end

-- data: title, text, optional icon or atlas (else the guild tabard), optional button = { label, onClick(button) }.
function UI.Toast(data)
  if #shown >= MAX_SHOWN then
    waiting[#waiting + 1] = data
    return
  end
  local t = table.remove(pool) or CreateToast()
  SetEmblem(t, data.icon, data.atlas)
  t.Title:SetText(data.title or "")
  t.Text:SetText(data.text or "")
  local b = data.button
  t.Button:SetShown(b ~= nil)
  if b then
    t.Button:SetText(b.label)
    t.Button:Enable()
    t.Button:SetScript("OnClick", function(self) b.onClick(self) end)
  end
  shown[#shown + 1] = t
  Layout()
  t:SetAlpha(1)
  t:Show()
  t.Glow:Show()
  t.GlowIn:Play()
  t.Shine:Show()
  t.ShineIn:Play()
  Fade(t, STAY)
  local sound = SOUNDKIT and (SOUNDKIT.UI_DIG_SITE_COMPLETION_TOAST or SOUNDKIT.UI_EPICLOOT_TOAST)
  if sound then PlaySound(sound) end
end

local function Grats(d)
  return function(button)
    if ZR.ChatLocked() then
      ZR.Msg("Chat is locked right now.")
      return
    end
    if C_GuildInfo.CanSpeakInGuildChat and not C_GuildInfo.CanSpeakInGuildChat() then
      ZR.Msg("Your rank can't talk in guild chat.")
      return
    end
    ZR.SendChat(ZR.Dings.GratsText(d), "GUILD")
    button:SetText("Sent!")
    button:Disable()
  end
end

local function ClassAtlas(class)
  return class and ("classicon-" .. class:lower()) or nil
end

ZR.On("Ding", function(d)
  local info = not d.class and ZR.RosterInfo(d.name)
  UI.Toast({
    atlas = ClassAtlas(d.class or (info and info.classFile)),
    title = ZR.ColorName(d.name, d.class),
    text = ZR.Dings.Text(d),
    button = { label = "Grats", onClick = Grats(d) },
  })
end)

-- Shows the look and lets it be dragged into place, without saying anything in chat.
function UI.PreviewDing()
  local _, class = UnitClass("player")
  UI.Toast({
    atlas = ClassAtlas(class),
    title = ZR.ColorName(ZR.PlayerName(), class),
    text = "reached level 42 (preview)",
    button = { label = "Grats", onClick = function(button) button:SetText("Sent!") button:Disable() end },
  })
end
