local _, JGH = ...
local UI = JGH.UI

local TAB_MESSAGE, TAB_INVITE, TAB_WHISPERS = 1, 2, 3
JGH.TAB_WHISPERS = TAB_WHISPERS

local views = {}

-- "A", "A and B", "A, B and C".
local function JoinNames(names)
  if #names < 2 then return names[1] or "" end
  return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

UI.RegisterFeature({
  key = "recruitment",
  title = "Recruitment",
  icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
  access = function() return JGH.IsRecruiter() end,
  lockText = function()
    local names = JGH.Ranks.AllowedNames()
    if #names == 0 or #names > 3 then return "Your guild rank can't use this page." end
    return "Only " .. JoinNames(names) .. " can use this page."
  end,
  lockSub = "Ask your Guild Master if you want to help with recruiting.",
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
