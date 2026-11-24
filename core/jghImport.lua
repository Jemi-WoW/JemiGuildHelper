local _, JGH = ...

-- WoW only loads ZUGZUGRebornDB for a folder with this name: the old addon or the import folder that replaces it.
local OLD_ADDON = "ZUGZUG-Reborn"

StaticPopupDialogs["JEMIGUILDHELPER_RELOAD"] = {
  text = "Jemi Guild Helper has replaced ZUGZUG Reborn and turned the old version off.\nReload now to finish.",
  button1 = "Reload",
  button2 = "Later",
  OnAccept = ReloadUI,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- Deep copies what dst lacks from src; dst wins where both have a value.
local function Fill(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if dst[k] == nil then dst[k] = {} end
      if type(dst[k]) == "table" then Fill(dst[k], v) end
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

-- Runs before InitDB when possible, so old settings beat the defaults.
function JGH.ImportOldDB()
  local old, db = ZUGZUGRebornDB, JemiGuildHelperDB
  if type(old) ~= "table" or type(db) ~= "table" or db.imported then return end
  Fill(db, old)
  db.imported = true
end

-- Disables the folder for every character; old code that ran this session needs a reload to go.
function JGH.RetireOldAddOn()
  if not C_AddOns.IsAddOnLoaded(OLD_ADDON) then return end
  local ok = pcall(C_AddOns.DisableAddOn, OLD_ADDON)
  if not _G.ZUGZUGReborn then return end
  if ok then
    StaticPopup_Show("JEMIGUILDHELPER_RELOAD")
  else
    JGH.Msg("Please delete the old ZUGZUG-Reborn folder from Interface\\AddOns.")
  end
end

-- Normally the old folder loads first; this catches it loading after us.
JGH.RegisterEvent("ADDON_LOADED", function(_, name)
  if name == OLD_ADDON then JGH.ImportOldDB() end
end)
