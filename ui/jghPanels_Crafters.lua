local _, JGH = ...
local UI = JGH.UI

UI.RegisterFeature({
  key = "crafters",
  title = "Crafters",
  -- Same art as the Professions window portrait.
  icon = "Interface\\Spellbook\\Spellbook-Icon",
  build = function(frame, inset)
    UI.BuildCrafters(frame, inset)
  end,
})
