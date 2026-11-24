local _, JGH = ...
local UI = JGH.UI

local TAB_MESSAGE, TAB_INVITE, TAB_WHISPERS = 1, 2, 3
JGH.TAB_WHISPERS = TAB_WHISPERS

local views = {}

UI.RegisterFeature({
  key = "recruitment",
  title = "Recruitment",
  icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
  access = function() return JGH.IsRecruiter() end,
  lockText = "Only officers and OGs can view this page.",
  lockSub = "Ask an officer if you want to help with recruiting.",
  tabs = { "Recruit Message", "Fast Invite", "Whispers" },

  tabLabel = function(index)
    if index ~= TAB_WHISPERS then return nil end
    local n = JGH.Inbox.Unread()
    return n > 0 and ("Whispers (%d)"):format(n) or "Whispers"
  end,

  build = function(frame, inset)
    views[TAB_MESSAGE] = UI.BuildRecruitMessage(frame, inset)
    views[TAB_INVITE] = UI.BuildFastInvite(frame, inset)
    views[TAB_WHISPERS] = UI.BuildWhispers(frame, inset)
  end,

  selectTab = function(index)
    for i, v in ipairs(views) do v:SetShown(i == index) end
  end,
})
