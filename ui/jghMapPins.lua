local _, JGH = ...
local UI = JGH.UI
local Map = JGH.Map

local SIZE = 18
local RING = 1.5
local FONT_SIZE = 10
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TAXI = { Horde = 132268, Alliance = 132239 }
local FALLBACK = { r = 0.2, g = 1, b = 0.4 }
local CLUSTER = { r = 1, g = 0.82, b = 0 }
local BADGE = 10
local LIFT = 16
local ROW = 5
local MAX_INSIDE = 10
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local MINI = 12
local PULSE = 4
local FOCUS_WAIT = 60
-- Minimap view diameters in yards per zoom level, for clients without C_Minimap.GetViewRadius.
local MINIMAP_YARDS = {
  outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
  indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}

local pins, rects, miniPins = {}, {}, {}
local dirty, gliding = true, false
local focus, pulse
local details, hovered = {}, nil
local MAX_DETAILS = 8
local seen = {}
local setUp, button

-- MapUtils members show as our pins, so its own dots stay hidden even while ours are toggled off.
local hooks = _G.D4GuildMapHooks or {}
_G.D4GuildMapHooks = hooks
hooks.JemiGuildHelper = { isHidden = function() return true end }

local function Rect(from, to)
  local key = from * 100000 + to
  if rects[key] == nil then
    local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(from, to)
    rects[key] = (minX and maxX and minY and maxY and minX < maxX and minY < maxY) and { minX, maxX, minY, maxY } or false
  end
  return rects[key] or nil
end

-- A position on one map, placed on another: directly, or by walking up parent maps.
local function Project(from, to, x, y)
  local visited = {}
  while from ~= to do
    if visited[from] then return nil end
    visited[from] = true
    local r = Rect(from, to)
    if r then return r[1] + x * (r[2] - r[1]), r[3] + y * (r[4] - r[3]) end
    r = Rect(to, from)
    if r then return (x - r[1]) / (r[2] - r[1]), (y - r[3]) / (r[4] - r[3]) end
    local info = C_Map.GetMapInfo(from)
    local parent = info and info.parentMapID
    if not parent or parent == 0 then return nil end
    r = Rect(from, parent)
    if not r then return nil end
    x, y = r[1] + x * (r[2] - r[1]), r[3] + y * (r[4] - r[3])
    from = parent
  end
  return x, y
end

local function ClassOf(m)
  local info = JGH.RosterInfo(m.name)
  return (info and info.classFile) or m.class
end

local function Waypoint(m)
  local can = C_Map.CanSetUserWaypointOnMap and UiMapPoint and C_Map.SetUserWaypoint
  if not can or not C_Map.CanSetUserWaypointOnMap(m.mapID) then
    JGH.Msg("A waypoint can't be placed on that map.")
    return
  end
  C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(m.mapID, m.x, m.y))
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
end

local function AddProfessions(tt, name)
  local Crafts = JGH.Crafts
  for _, prof in ipairs(Crafts.PROFESSIONS) do
    local p = Crafts.GetProf(name, prof.id)
    if p and (p.m or 0) > 0 then
      tt:AddDoubleLine("|T" .. prof.icon .. ":14:14|t " .. Crafts.ProfName(prof.id), p.r .. "/" .. p.m,
        1, 0.82, 0, 1, 1, 1)
    end
  end
  -- Missing means an older addon version, so those stay out rather than read as not learned.
  for _, prof in ipairs(Crafts.SECONDARY) do
    local p = Crafts.GetProf(name, prof.id)
    if p then
      local label = "|T" .. prof.icon .. ":14:14|t " .. Crafts.ProfName(prof.id)
      if (p.m or 0) > 0 then
        tt:AddDoubleLine(label, p.r .. "/" .. p.m, 1, 0.82, 0, 1, 1, 1)
      else
        tt:AddDoubleLine(label, "Not learned", 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
      end
    end
  end
end

local function PlayedText(secs)
  secs = math.floor(secs)
  return ("%dd, %dh, %dm, %ds"):format(math.floor(secs / 86400), math.floor(secs % 86400 / 3600),
    math.floor(secs % 3600 / 60), secs % 60)
end

-- One member's lines, shared by the single tooltip and the Shift view of a group.
local function FillMember(tt, m)
  local info = JGH.RosterInfo(m.name)
  GameTooltip_SetTitle(tt, JGH.ColorName(m.name, ClassOf(m)))
  local bits = {}
  if info and info.rank then bits[#bits + 1] = info.rank end
  local level = (info and info.level) or m.level
  if level and level > 0 then bits[#bits + 1] = (LEVEL or "Level") .. " " .. level end
  if #bits > 0 then tt:AddLine(table.concat(bits, ", "), 1, 1, 1) end
  if m.played then
    tt:AddLine("Played " .. PlayedText(m.played + GetTime() - m.playedAt), 0.8, 0.8, 0.8)
  end
  local mapInfo = C_Map.GetMapInfo(m.mapID)
  if m.instance then
    tt:AddLine("In " .. (m.instance.name ~= "" and m.instance.name or (m.instance.raid and "a raid" or "a dungeon")), 0.6, 0.8, 1)
    if mapInfo and mapInfo.name then tt:AddLine("Entrance in " .. mapInfo.name, 0.7, 0.7, 0.7) end
  elseif mapInfo and mapInfo.name then
    tt:AddLine(mapInfo.name, 0.7, 0.7, 0.7)
  end
  if m.taxi then tt:AddLine("On a flight path", 1, 0.82, 0) end
  AddProfessions(tt, m.name)
  tt:AddLine(" ")
  tt:AddLine(("Updated %ds ago%s"):format(math.max(0, math.floor(GetTime() - m.at)),
    m.source == "MapUtils" and ", shared by MapUtils" or ""), 0.5, 0.5, 0.5)
end

local function MemberTooltip(pin, m)
  GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
  FillMember(GameTooltip, m)
  GameTooltip:AddLine("Right-click for more, Shift-click for a waypoint.", 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

local function DetailTooltip(i)
  if i == 1 then return GameTooltip end
  local tt = details[i] or CreateFrame("GameTooltip", "JemiGuildHelperMapTooltip" .. i, UIParent, "GameTooltipTemplate")
  details[i] = tt
  tt:SetScale(GameTooltip:GetScale())
  return tt
end

local function HideDetails()
  for _, tt in pairs(details) do tt:Hide() end
end

-- Each member's full tooltip side by side, starting a new row at the screen edge.
local function GroupDetails(pin, list)
  local shown = math.min(#list, MAX_DETAILS)
  local rowStart, rowBottom, prev
  for i = 1, shown do
    local tt = DetailTooltip(i)
    tt:SetOwner(pin, i == 1 and "ANCHOR_RIGHT" or "ANCHOR_NONE")
    FillMember(tt, list[i])
    if i == shown and #list > shown then tt:AddLine(("And %d more"):format(#list - shown), 0.6, 0.6, 0.6) end
    tt:Show()
    if i > 1 then
      local screen = UIParent:GetRight() * UIParent:GetEffectiveScale() / tt:GetEffectiveScale()
      tt:ClearAllPoints()
      if (prev:GetRight() or 0) + tt:GetWidth() > screen then
        tt:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", rowStart:GetLeft() or 0, rowBottom - 2)
        rowStart, rowBottom = tt, nil
      else
        tt:SetPoint("TOPLEFT", prev, "TOPRIGHT", 2, 0)
      end
    else
      rowStart = tt
    end
    local bottom = tt:GetBottom() or 0
    rowBottom = math.min(rowBottom or bottom, bottom)
    prev = tt
  end
end

local function GroupTooltip(pin, list)
  if IsShiftKeyDown() then return GroupDetails(pin, list) end
  GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
  GameTooltip_SetTitle(GameTooltip, #list .. " guild members")
  for _, m in ipairs(list) do
    local mapInfo = C_Map.GetMapInfo(m.mapID)
    local where = (m.instance and m.instance.name ~= "" and m.instance.name) or (mapInfo and mapInfo.name) or ""
    GameTooltip:AddDoubleLine(JGH.ColorName(m.name, ClassOf(m)), where, 1, 1, 1, 0.7, 0.7, 0.7)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Hold Shift to see each of them.", 0.6, 0.6, 0.6)
  GameTooltip:AddLine("Right-click to pick who to whisper.", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function PinEnter(pin)
  hovered = pin
  HideDetails()
  if #pin.list == 1 then MemberTooltip(pin, pin.list[1]) else GroupTooltip(pin, pin.list) end
end

local function PinLeave()
  hovered = nil
  HideDetails()
  GameTooltip_Hide()
end

local function ClusterMenu(pin)
  if not MenuUtil or not MenuUtil.CreateContextMenu then return end
  MenuUtil.CreateContextMenu(pin, function(_, root)
    root:CreateTitle(WHISPER or "Whisper")
    for _, m in ipairs(pin.list) do
      root:CreateButton(JGH.ColorName(m.name, ClassOf(m)), function() UI.Whisper(m.name) end)
    end
  end)
end

-- Plain left-click does nothing, so clicking around the map never opens a whisper by accident.
local function PinClick(pin, button)
  if button == "RightButton" then
    if #pin.list > 1 then return ClusterMenu(pin) end
    UI.NameMenu(pin, pin.list[1].name, ClassOf(pin.list[1]), true)
  elseif IsShiftKeyDown() and #pin.list == 1 then
    Waypoint(pin.list[1])
  end
end

local function CreatePin(canvas)
  local pin = CreateFrame("Button", nil, canvas)
  pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  pin.Shadow = pin:CreateTexture(nil, "BACKGROUND", nil, -1)
  pin.Shadow:SetTexture(MASK)
  pin.Shadow:SetVertexColor(0, 0, 0, 0.85)
  pin.Ring = pin:CreateTexture(nil, "BACKGROUND")
  pin.Ring:SetAllPoints()
  pin.Ring:SetTexture(MASK)
  pin.Icon = pin:CreateTexture(nil, "ARTWORK")
  pin.Mask = pin:CreateMaskTexture()
  pin.Mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  pin.Mask:SetAllPoints(pin.Icon)
  pin.Icon:AddMaskTexture(pin.Mask)
  pin.Count = pin:CreateFontString(nil, "OVERLAY")
  pin.Count:SetPoint("CENTER")
  pin.Badge = pin:CreateTexture(nil, "OVERLAY", nil, 1)
  pin:SetScript("OnEnter", PinEnter)
  pin:SetScript("OnLeave", PinLeave)
  pin:SetScript("OnHide", function(self)
    if hovered == self then PinLeave() elseif GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  pin:SetScript("OnClick", PinClick)
  return pin
end

local function SetBadge(pin, instance, scale)
  if not instance then
    pin.Badge:Hide()
    return
  end
  local atlas = instance.raid and "Raid" or "Dungeon"
  if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
    pin.Badge:SetAtlas(atlas)
  else
    pin.Badge:SetTexture(SKULL)
  end
  pin.Badge:SetSize(BADGE / scale, BADGE / scale)
  pin.Badge:ClearAllPoints()
  pin.Badge:SetPoint("CENTER", pin, "BOTTOMRIGHT", -2 / scale, 2 / scale)
  pin.Badge:Show()
end

-- Sized against the canvas scale so pins look the same at every zoom.
local function SetupPin(pin, list, scale)
  pin.list = list
  local size, ring = SIZE / scale, RING / scale
  pin:SetSize(size, size)
  SetBadge(pin, list[1].instance, scale)
  -- A dark edge keeps yellow and white class colors visible on the map.
  pin.Shadow:ClearAllPoints()
  pin.Shadow:SetPoint("TOPLEFT", -1 / scale, 1 / scale)
  pin.Shadow:SetPoint("BOTTOMRIGHT", 1 / scale, -1 / scale)
  pin.Icon:ClearAllPoints()
  pin.Icon:SetPoint("TOPLEFT", ring, -ring)
  pin.Icon:SetPoint("BOTTOMRIGHT", -ring, ring)
  pin.Count:SetFont(STANDARD_TEXT_FONT, FONT_SIZE / scale, "OUTLINE")
  if #list > 1 then
    pin.Ring:SetVertexColor(CLUSTER.r, CLUSTER.g, CLUSTER.b)
    pin.Icon:SetColorTexture(0.08, 0.08, 0.08)
    pin.Count:SetText(#list)
    pin.Count:Show()
    return
  end
  pin.Count:Hide()
  local m = list[1]
  local class = ClassOf(m)
  local color = (class and RAID_CLASS_COLORS[class]) or FALLBACK
  pin.Ring:SetVertexColor(color.r, color.g, color.b)
  local taxi = m.taxi and TAXI[UnitFactionGroup("player") or ""]
  if taxi then
    pin.Icon:SetTexture(taxi)
    pin.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  elseif class then
    pin.Icon:SetAtlas("classicon-" .. class:lower())
  else
    pin.Icon:SetColorTexture(color.r, color.g, color.b)
  end
end

local pinLevel

-- Read in combat too: it only reads, and the canvas fallback sits under the map art.
local function PinLevel(canvas)
  local manager = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
  if manager and manager.GetValidFrameLevel then
    local ok, level = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_GROUP_MEMBER")
    if ok and type(level) == "number" then pinLevel = level end
  end
  return pinLevel or canvas:GetFrameLevel() + 30
end

-- Combat can hide group membership; an extra pin beats an error that draws none.
local function InGroup(name)
  local party, raid = UnitInParty(name), UnitInRaid(name)
  if JGH.IsSecret(party) or JGH.IsSecret(raid) then return false end
  return (party or raid) and true or false
end

-- Nearby members share one pin, so a busy town stays readable.
local function Cluster(points, size)
  table.sort(points, function(a, b) return a.m.name < b.m.name end)
  local groups = {}
  for _, p in ipairs(points) do
    local hit
    for _, g in ipairs(groups) do
      local dx, dy = g.x - p.x, g.y - p.y
      if dx * dx + dy * dy < size * size then
        hit = g
        break
      end
    end
    if hit then
      hit.list[#hit.list + 1] = p.m
    else
      groups[#groups + 1] = { x = p.x, y = p.y, list = { p.m } }
    end
  end
  return groups
end

-- Members in one dungeon line up above its entrance, closest row first, instead of merging into one pin.
local function InsideSlots(group, scale, out)
  local list = group.list
  table.sort(list, function(a, b) return a.name < b.name end)
  local items = {}
  for i = 1, math.min(#list, MAX_INSIDE) do items[i] = { list[i] } end
  if #list > MAX_INSIDE then
    local rest = {}
    for i = MAX_INSIDE, #list do rest[#rest + 1] = list[i] end
    items[MAX_INSIDE] = rest
  end
  local ex, ey = group.x / #list, group.y / #list
  local step, lift = (SIZE + 2) / scale, LIFT / scale
  for i, item in ipairs(items) do
    local row = math.floor((i - 1) / ROW)
    local inRow = math.min(ROW, #items - row * ROW)
    local col = (i - 1) % ROW
    out[#out + 1] = { list = item, x = ex + (col - (inRow - 1) / 2) * step, y = ey - lift - row * step }
  end
end

local function Pulse(canvas)
  if pulse then return pulse end
  pulse = CreateFrame("Frame", nil, canvas)
  pulse.Glow = pulse:CreateTexture(nil, "BACKGROUND")
  pulse.Glow:SetPoint("CENTER")
  pulse.Glow:SetTexture(MASK)
  pulse.Glow:SetVertexColor(CLUSTER.r, CLUSTER.g, CLUSTER.b)
  pulse.Glow:SetBlendMode("ADD")
  pulse:SetScript("OnUpdate", function(self)
    local age = focus and focus.start and GetTime() - focus.start
    if not age or age > PULSE then
      if age then focus = nil end
      self:Hide()
      return
    end
    local t = age % 1
    self.Glow:SetSize(self.base * (1 + 1.5 * t), self.base * (1 + 1.5 * t))
    self.Glow:SetAlpha(0.9 * (1 - t))
  end)
  return pulse
end

-- Rings the member picked with Show on map for a few seconds, once their pin is on screen.
local function PlacePulse(canvas, found, scale, level)
  if not focus or not found then
    if pulse then pulse:Hide() end
    return
  end
  focus.start = focus.start or GetTime()
  local p = Pulse(canvas)
  p.base = SIZE / scale
  p:SetSize(p.base, p.base)
  p:SetFrameLevel(math.max(level - 1, 0))
  p:ClearAllPoints()
  p:SetPoint("CENTER", found)
  p:Show()
end

local function Draw()
  dirty = false
  gliding = false
  local canvas = WorldMapFrame:GetCanvas()
  local mapID = WorldMapFrame:GetMapID()
  local count = 0
  local found
  local now = GetTime()
  if focus and not focus.start and now - focus.at > FOCUS_WAIT then focus = nil end
  local scale = canvas and canvas:GetScale()
  local width, height = canvas and canvas:GetWidth() or 0, canvas and canvas:GetHeight() or 0
  if mapID and Map.Showing() and scale and scale > 0 and width > 0 and height > 0 then
    local points, inside = {}, {}
    for name, m in pairs(Map.Active()) do
      -- Blizzard already draws party and raid members, but not ones inside a dungeon.
      if m.instance or not InGroup(name) then
        local px, py, moving = Map.Position(m, now)
        gliding = gliding or moving
        local x, y = Project(m.mapID, mapID, px, py)
        if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
          x, y = width * x, height * y
          if m.instance then
            local g = inside[m.instance.id] or { list = {}, x = 0, y = 0 }
            inside[m.instance.id] = g
            g.list[#g.list + 1] = m
            g.x, g.y = g.x + x, g.y + y
          else
            points[#points + 1] = { m = m, x = x, y = y }
          end
        end
      end
    end
    local slots = Cluster(points, SIZE / scale)
    for _, g in pairs(inside) do InsideSlots(g, scale, slots) end
    local level = PinLevel(canvas)
    for _, g in ipairs(slots) do
      count = count + 1
      local pin = pins[count]
      if not pin then
        pin = CreatePin(canvas)
        pins[count] = pin
      end
      if pin:GetFrameLevel() ~= level then pin:SetFrameLevel(level) end
      SetupPin(pin, g.list, scale)
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", canvas, "TOPLEFT", g.x, -g.y)
      pin:Show()
      if focus then
        for _, m in ipairs(g.list) do
          if m.name == focus.name then found = pin end
        end
      end
    end
    PlacePulse(canvas, found, scale, level)
  end
  for i = count + 1, #pins do pins[i]:Hide() end
end

function UI.ShowOnMap(name)
  local m = Map.Get(name)
  if not m then
    JGH.Msg(name .. " isn't on the map right now.")
    return
  end
  if not Map.Showing() then Map.SetShowing(true) end
  focus = { name = name, at = GetTime() }
  dirty = true
  if WorldMapFrame:IsShown() then
    WorldMapFrame:SetMapID(m.mapID)
  elseif InCombatLockdown() then
    -- Opening the map from an addon is blocked in combat, so it waits for the player to open it.
    JGH.Msg("Open your map to see " .. name .. ".")
  else
    OpenWorldMap(m.mapID)
  end
end

local function OnMapShown()
  dirty = true
  local m = focus and not focus.start and Map.Get(focus.name)
  if m and WorldMapFrame:GetMapID() ~= m.mapID then WorldMapFrame:SetMapID(m.mapID) end
end

-- The guild roster and chat name menus get Show on map too, for members with a position.
if Menu and Menu.ModifyMenu then
  for _, tag in ipairs({ "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_GUILD", "MENU_UNIT_FRIEND" }) do
    Menu.ModifyMenu(tag, function(_, root, data)
      local name = data and data.name
      if type(name) ~= "string" or JGH.IsSecret(name) then return end
      name = JGH.StripRealm(name)
      if not Map.Get(name) then return end
      root:CreateDivider()
      root:CreateButton("Show on map", function() UI.ShowOnMap(name) end)
    end)
  end
end

local function OnUpdate(self, elapsed)
  self.elapsed = (self.elapsed or 0) + elapsed
  if self.elapsed < (gliding and 0.03 or 0.1) then return end
  self.elapsed = 0
  local canvas = WorldMapFrame:GetCanvas()
  local mapID, scale, width = WorldMapFrame:GetMapID(), canvas:GetScale(), canvas:GetWidth()
  if not dirty and not gliding and seen.mapID == mapID and seen.scale == scale and seen.width == width then return end
  seen.mapID, seen.scale, seen.width = mapID, scale, width
  Draw()
end

local function UpdateButton()
  if not button then return end
  local on = Map.Showing()
  button.Icon:SetDesaturated(not on)
  button.Icon:SetAlpha(on and 1 or 0.4)
  button.Background:SetAlpha(on and 1 or 0.4)
end

local function ButtonTooltip(self)
  local on = Map.Showing()
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip_SetTitle(GameTooltip, JGH.TITLE)
  GameTooltip:AddDoubleLine("Guild members", on and "Shown" or "Hidden", 1, 1, 1,
    on and 0.2 or 1, on and 1 or 0.3, on and 0.2 or 0.3)
  GameTooltip:AddLine(on and "Click to hide them." or "Click to show them.", 0.6, 0.6, 0.6)
  if Map.Sharing() then GameTooltip:AddLine("Guild members still see you either way.", 0.6, 0.6, 0.6) end
  GameTooltip:Show()
end

local function ButtonClick(self)
  local on = not Map.Showing()
  PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
  Map.SetShowing(on)
  ButtonTooltip(self)
end

local function StyleButton(b)
  b:SetSize(32, 32)
  b:SetFrameStrata("HIGH")
  b.Background = b:CreateTexture(nil, "BACKGROUND")
  b.Background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  b.Background:SetSize(24, 24)
  b.Background:SetPoint("CENTER")
  b.Icon = b:CreateTexture(nil, "ARTWORK")
  b.Icon:SetTexture(JGH.ICON_TEXTURE)
  b.Icon:SetSize(20, 20)
  b.Icon:SetPoint("CENTER")
  b.Icon:SetMask(MASK)
  b.Border = b:CreateTexture(nil, "OVERLAY")
  b.Border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b.Border:SetSize(54, 54)
  b.Border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
  b:SetScript("OnMouseDown", function(self) self.Icon:SetPoint("CENTER", 1, -1) end)
  b:SetScript("OnMouseUp", function(self) self.Icon:SetPoint("CENTER") end)
  b:SetScript("OnClick", ButtonClick)
  b:SetScript("OnEnter", ButtonTooltip)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b.Refresh = UpdateButton
end

local function Container()
  return WorldMapFrame.GetCanvasContainer and WorldMapFrame:GetCanvasContainer() or WorldMapFrame.ScrollContainer
end

-- Without the shared button library, take the first free slot in the column other addons stack down the left edge.
local function PlaceButton()
  local box = Container()
  local left, top = box:GetLeft(), box:GetTop()
  if not left or not top then return end
  local taken = {}
  for _, parent in ipairs({ WorldMapFrame, box, WorldMapFrame.BorderFrame }) do
    for _, f in ipairs({ parent:GetChildren() }) do
      if f ~= button and f:IsShown() then
        local l, t, w, h = f:GetLeft(), f:GetTop(), f:GetWidth(), f:GetHeight()
        if l and t and w >= 16 and w <= 48 and h >= 16 and h <= 48 and math.abs(l - left) < 40 then
          local slot = math.floor((top - t) / 32 + 0.5)
          if slot >= 0 then taken[slot] = true end
        end
      end
    end
  end
  local slot = 0
  while taken[slot] do slot = slot + 1 end
  button:ClearAllPoints()
  button:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -32 * slot)
end

-- Made on first open, once every other addon has loaded its buttons.
local function CreateButton()
  if button then return end
  local lib = LibStub and LibStub("Krowi_WorldMapButtons-1.4", true)
  if lib then
    button = lib:Add(nil, "Button")
    StyleButton(button)
  else
    button = CreateFrame("Button", "JemiGuildHelperMapButton", WorldMapFrame)
    StyleButton(button)
    -- Other addons place theirs when the map opens, so wait for them.
    WorldMapFrame:HookScript("OnShow", function() C_Timer.After(0, PlaceButton) end)
    Container():HookScript("OnSizeChanged", PlaceButton)
    C_Timer.After(0, PlaceButton)
  end
  UpdateButton()
end

local function Setup()
  if setUp or not WorldMapFrame or not WorldMapFrame.GetCanvas or not C_Map.GetMapRectOnMap then return end
  setUp = true
  local updater = CreateFrame("Frame", nil, WorldMapFrame)
  updater:SetScript("OnUpdate", OnUpdate)
  WorldMapFrame:HookScript("OnShow", function()
    OnMapShown()
    CreateButton()
  end)
end

local function MinimapRadius()
  if C_Minimap and C_Minimap.GetViewRadius then
    local ok, yards = pcall(C_Minimap.GetViewRadius)
    if ok and type(yards) == "number" and yards > 0 then return yards end
  end
  local sizes = MINIMAP_YARDS[IsIndoors() and "indoor" or "outdoor"]
  return (sizes[Minimap:GetZoom()] or sizes[0]) / 2
end

local vec = CreateVector2D and CreateVector2D(0, 0)

-- World yards, which work across zone borders: x points north, y points west.
local function WorldPos(mapID, x, y)
  if not vec or not C_Map.GetWorldPosFromMapPos then return end
  vec:SetXY(x, y)
  local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, vec)
  if ok and continent and pos then return continent, pos.x, pos.y end
end

local function MemberWorld(m, x, y)
  if m.worldX ~= x or m.worldY ~= y then
    m.worldX, m.worldY = x, y
    m.continent, m.north, m.west = WorldPos(m.mapID, x, y)
  end
  return m.continent, m.north, m.west
end

local function DrawMinimap()
  local count = 0
  local mapID, x, y = Map.OwnPosition()
  local continent, north, west
  if mapID and Map.Showing() and Map.MinimapShowing() then continent, north, west = WorldPos(mapID, x, y) end
  if continent then
    local half = Minimap:GetWidth() / 2
    local perYard = half / MinimapRadius()
    local edge = half - MINI / 2
    local round = not GetMinimapShape or GetMinimapShape() == "ROUND"
    local facing = GetCVar("rotateMinimap") == "1" and GetPlayerFacing()
    if JGH.IsSecret(facing) then facing = nil end
    local sin, cos = math.sin(facing or 0), math.cos(facing or 0)
    local now, level = GetTime(), Minimap:GetFrameLevel() + 5
    for name, m in pairs(Map.Active()) do
      -- Dungeon members only stand at the entrance on paper, and Blizzard draws group members.
      if not m.instance and not InGroup(name) then
        local c, n, w = MemberWorld(m, Map.Position(m, now))
        if c == continent then
          local east, up = (west - w) * perYard, (n - north) * perYard
          local sx, sy = east * cos + up * sin, -east * sin + up * cos
          local shown = round and sx * sx + sy * sy <= edge * edge or not round and math.abs(sx) <= edge and math.abs(sy) <= edge
          if shown then
            count = count + 1
            local pin = miniPins[count]
            if not pin then
              pin = CreatePin(Minimap)
              miniPins[count] = pin
            end
            if pin:GetFrameLevel() ~= level then pin:SetFrameLevel(level) end
            pin.one = pin.one or {}
            pin.one[1] = m
            SetupPin(pin, pin.one, SIZE / MINI)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", Minimap, "CENTER", sx, sy)
            pin:Show()
          end
        end
      end
    end
  end
  for i = count + 1, #miniPins do miniPins[i]:Hide() end
end

local function SetupMinimap()
  if not Minimap or not C_Map.GetWorldPosFromMapPos then return end
  local updater = CreateFrame("Frame", nil, Minimap)
  updater:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.05 then return end
    self.elapsed = 0
    DrawMinimap()
  end)
end

JGH.On("MapChanged", function()
  dirty = true
  UpdateButton()
end)
JGH.On("RosterChanged", function() dirty = true end)
JGH.RegisterEvent("MODIFIER_STATE_CHANGED", function()
  if hovered and hovered:IsShown() and hovered:IsMouseOver() then PinEnter(hovered) end
end)
JGH.RegisterEvent("GROUP_ROSTER_UPDATE", function() dirty = true end)
EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Setup)
-- Some clients build the world map at startup instead of as its own addon.
JGH.RegisterEvent("PLAYER_LOGIN", function()
  Setup()
  SetupMinimap()
end)
