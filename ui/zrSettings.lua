local _, ZR = ...

-- Options > AddOns > ZUGZUG Reborn; pages and settings are added in Options.Init below.
local Options = {}
ZR.Options = Options

local root

-- A page listed under ZUGZUG Reborn.
function Options.Page(name)
  return Settings.RegisterVerticalLayoutSubcategory(root, name)
end

-- Every setting is saved as ZR.DB()[key]; onChange runs after a change.
local function Register(page, key, varType, name, default, onChange)
  local function get()
    local v = ZR.DB()[key]
    if v == nil then return default end
    return v
  end
  local function set(v)
    ZR.DB()[key] = v
    if onChange then onChange(v) end
  end
  return Settings.RegisterProxySetting(page, "ZUGZUGREBORN_" .. key:upper(), varType, name, default, get, set)
end

function Options.Checkbox(page, key, name, default, tooltip, onChange)
  local setting = Register(page, key, Settings.VarType.Boolean, name, default, onChange)
  return setting, Settings.CreateCheckbox(page, setting, tooltip)
end

-- fmt turns the value into the text beside the slider, e.g. function(v) return v .. " sec" end.
function Options.Slider(page, key, name, default, min, max, step, tooltip, fmt, onChange)
  local setting = Register(page, key, Settings.VarType.Number, name, default, onChange)
  local opts = Settings.CreateSliderOptions(min, max, step)
  opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt or tostring)
  return setting, Settings.CreateSlider(page, setting, opts, tooltip)
end

-- Indents the child under its checkbox and greys it out while that box is off.
function Options.DependsOn(child, parent, isOn)
  if child.SetParentInitializer then child:SetParentInitializer(parent, isOn) end
end

-- choices is a list of { value, label }.
function Options.Dropdown(page, key, name, default, choices, tooltip, onChange)
  local varType = type(default) == "number" and Settings.VarType.Number or Settings.VarType.String
  local setting = Register(page, key, varType, name, default, onChange)
  local function list()
    local c = Settings.CreateControlTextContainer()
    for _, choice in ipairs(choices) do c:Add(choice[1], choice[2]) end
    return c:GetData()
  end
  Settings.CreateDropdown(page, setting, list, tooltip)
  return setting
end

function Options.Header(page, text)
  Settings.GetLayout(page):AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function AboutPanel()
  local panel = CreateFrame("Frame")
  local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  local last
  local function Line(text, font, gap)
    local fs = panel:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    if last then fs:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -(gap or 8)) else fs:SetPoint("TOPLEFT", 16, -16) end
    fs:SetText(text)
    last = fs
  end
  Line(ZR.TITLE, "GameFontNormalLarge")
  Line("Guild crafters, raids and dings, inside the Guild & Communities window.")
  Line("Version: " .. (meta and meta(ZR.ADDON, "Version") or "?"), nil, 18)
  Line("Author: Jamie/Jemi")
  return panel
end

-- Opens on ZUGZUG Reborn with its pages unfolded.
function Options.Open()
  if not root then return end
  root:SetExpanded(true)
  Settings.OpenToCategory(root:GetID())
end

-- Runs at login, once saved settings are loaded.
function Options.Init()
  if root or not (Settings and Settings.RegisterVerticalLayoutSubcategory) then return end
  root = Settings.RegisterCanvasLayoutCategory(AboutPanel(), ZR.TITLE)
  Settings.RegisterAddOnCategory(root)

  local ding = Options.Page("Ding popup")
  Options.ding = ding
  local _, show = Options.Checkbox(ding, "dings", "Show ding popups", true,
    "Pop up when a guild member levels up or reaches 300 in a profession.")
  local _, from = Options.Slider(ding, "dingMinLevel", "Start from level", ZR.Dings.MIN_LEVEL, 2, 60, 1,
    "Guild members' level-ups below this level don't pop up.")
  Options.DependsOn(from, show, ZR.Dings.Enabled)
end
