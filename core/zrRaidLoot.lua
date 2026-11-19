local _, ZR = ...
local Raids = ZR.Raids

-- Stands in for loot that isn't known yet, with Zesty Clam Meat's tooltip.
Raids.TEMP_ITEM = 7974
Raids.TEMP_NAME = "TEMP ITEM"

-- Items are { id, name, drop % }: Onyxia's Classic table, and only the temp item for the unreleased Hyjal raids.
Raids.LOOT = {
  barrow = {
    { name = "Chillhowl" },
    { name = "Elder Tangleclaw" },
    { name = "Khalith the Dreadspinner" },
    { name = "Well of Sorrow" },
    { name = "Amethrax" },
    { name = "Del'lynar Songwood" },
    { name = "Ravus and Darlissa" },
    { name = "Sonya Darkhallow" },
  },
  hyjal = {
    { name = "Bandalar" },
    { name = "Ancient of Decay" },
    { name = "Time-Lost Battalion" },
    { name = "Sylvestris Dusksong" },
    { name = "Old Gloomlurker" },
    { name = "Gharalis the Abyssal" },
    { name = "Kathris the Haunted" },
    { name = "Anara Chillwind" },
    { name = "Elder Minderel" },
    { name = "Tracker Stillwind" },
    { name = "Council of Thorns" },
    { name = "Nythus the Dreambound" },
    { name = "The Wild King" },
  },
  onyxia = {
    { name = "Onyxia", items = {
      { 16900, "Stormrage Cover", 11 },
      { 16908, "Bloodfang Hood", 11 },
      { 16914, "Netherwind Crown", 11 },
      { 16921, "Halo of Transcendence", 11 },
      { 16929, "Nemesis Skullcap", 11 },
      { 16939, "Dragonstalker's Helm", 11 },
      { 16947, "Helmet of Ten Storms", 11 },
      { 16955, "Judgement Crown", 11 },
      { 16963, "Helm of Wrath", 11 },
      { 17068, "Deathbringer", 13 },
      { 17075, "Vis'kag the Bloodletter", 12 },
      { 18813, "Ring of Binding", 18 },
      { 17078, "Sapphiron Drape", 18 },
      { 18205, "Eskhandar's Collar", 15 },
      { 17064, "Shard of the Scale", 17 },
      { 17067, "Ancient Cornerstone Grimoire", 17 },
      { 17966, "Onyxia Hide Backpack", 23 },
      { 18705, "Mature Black Dragon Sinew", 15 },
      { 18422, "Head of Onyxia", 100 },
    } },
  },
}

-- The raid's bosses plus trash, each ending with the temp item.
function Raids.Bosses(raidKey)
  local out = {}
  local list = Raids.LOOT[raidKey] or {}
  for _, boss in ipairs(list) do out[#out + 1] = boss end
  out[#out + 1] = { name = "Trash" }
  for _, boss in ipairs(out) do
    boss.all = {}
    for _, it in ipairs(boss.items or {}) do boss.all[#boss.all + 1] = { id = it[1], name = it[2], chance = it[3] } end
    boss.all[#boss.all + 1] = { id = Raids.TEMP_ITEM, name = Raids.TEMP_NAME, temp = true }
  end
  return out
end

-- Name for lists: the temp item keeps its label, real items their game name once cached.
function Raids.ItemName(id)
  if id == Raids.TEMP_ITEM then return Raids.TEMP_NAME end
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if name then return name end
  for _, bosses in pairs(Raids.LOOT) do
    for _, boss in ipairs(bosses) do
      for _, it in ipairs(boss.items or {}) do
        if it[1] == id then return it[2] end
      end
    end
  end
  return "Item " .. id
end

function Raids.ItemIcon(id)
  local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Quality colored, plain white for the temp item.
function Raids.ItemColor(id)
  if id == Raids.TEMP_ITEM then return "ffffffff" end
  local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 4]
  return c and c.hex and c.hex:gsub("|c", "") or "ffa335ee"
end

-- Fills tooltip for an item; items the game has no data for get a plain note instead of waiting forever.
function Raids.ShowItemTooltip(tooltip, id)
  local cached = C_Item and C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(id)
  if cached then
    tooltip:SetItemByID(id)
    return
  end
  if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
  tooltip:SetText(("|c%s%s|r"):format(Raids.ItemColor(id), Raids.ItemName(id)))
  tooltip:AddLine("Item information unknown", 0.6, 0.6, 0.6)
end

-- A tooltip still showing an item refreshes once the game sends its data.
ZR.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, id, ok)
  if not ok or not GameTooltip:IsShown() then return end
  local owner = GameTooltip:GetOwner()
  if owner and owner.itemID == id and owner:GetScript("OnEnter") then owner:GetScript("OnEnter")(owner) end
end)

function Raids.PreloadLoot(raidKey)
  if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
  for _, boss in ipairs(Raids.Bosses(raidKey)) do
    for _, it in ipairs(boss.all) do C_Item.RequestLoadItemDataByID(it.id) end
  end
end
