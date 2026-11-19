local _, ZR = ...
local UI = ZR.UI

UI.RegisterFeature({
  key = "raids",
  title = "Raids",
  icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
  build = function(frame, inset)
    UI.BuildRaids(frame, inset):Show()
  end,
})
