local _, JGH = ...

local readyGuild

-- Guild data arrives a little after login.
local function CheckGuildReady()
  local g, name = JGH.GDB()
  if not g or readyGuild == name then return end
  readyGuild = name
  JGH.Contacts.Prune()
  JGH.Fire("GuildReady")
end

JGH.RegisterEvent("ADDON_LOADED", function(_, name)
  if name ~= JGH.ADDON then return end
  JGH.InitDB()
end)

JGH.RegisterEvent("PLAYER_LOGIN", function()
  JGH.CharDB()
  JGH.UI.GuildFrame.Init()
  JGH.ApplyMinimapButton()
  JGH.Sync.Init()
  JGH.CraftSync.Init()
  JGH.Map.Init()
  JGH.Dings.Init()
  JGH.Raids.Init()
  JGH.Loot.Init()
  JGH.Options.Init()
  JGH.RequestRoster()
  JGH.CheckOfficer()
  CheckGuildReady()
end)

JGH.RegisterEvent("GUILD_ROSTER_UPDATE", CheckGuildReady)
JGH.RegisterEvent("PLAYER_GUILD_UPDATE", CheckGuildReady)
