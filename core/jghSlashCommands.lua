local _, JGH = ...

SLASH_JEMIGUILDHELPER1 = "/guildhelper"
SLASH_JEMIGUILDHELPER2 = "/jgh"

local function PrintHelp()
  JGH.Msg("Commands:")
  JGH.Msg("  |cffffd100/jgh|r - open the Guild window page where you left off")
  JGH.Msg("  |cffffd100/jgh recruit|r - open Recruitment")
  JGH.Msg("  |cffffd100/jgh whispers|r - open the Whispers tab")
  JGH.Msg("  |cffffd100/jgh craft <item>|r - find who in the guild can craft it")
  JGH.Msg("  |cffffd100/jgh raids|r - open raid sign-ups")
  JGH.Msg("  |cffffd100/jgh clock 12|r or |cffffd10024|r - how raid times are shown")
  JGH.Msg("  |cffffd100/jgh roll [item]|r - start a roll for an item (raid leader, assistant or master looter)")
  JGH.Msg("  |cffffd100/jgh dings on|r or |cffffd100off|r - guild level-up popups (|cffffd100preview|r to place them, |cffffd100reset|r to move them back)")
  JGH.Msg("  |cffffd100/jgh minimap|r - show or hide the minimap icon")
  JGH.Msg("  |cffffd100/jgh map on|r or |cffffd100off|r - guild members on the world map")
  JGH.Msg("  |cffffd100/jgh map minimap on|r or |cffffd100off|r - guild members on the minimap")
  JGH.Msg("  |cffffd100/jgh invite chat|r or |cffffd100copy|r - how Invite hands you /ginvite")
  JGH.Msg("  |cffffd100/jgh sync on|r or |cffffd100off|r - share contacts with other officers")
  JGH.Msg("  |cffffd100/jgh days <n>|r - hide contacted players for n days (now " .. (JGH.DB().hideDays or 3) .. ")")
  JGH.Msg("  |cffffd100/jgh resetcontacts|r - forget every whisper, invite and decline")
end

SlashCmdList["JEMIGUILDHELPER"] = function(msg)
  local raw = msg or ""
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")

  if cmd == "" then
    JGH.OpenPage()
    return
  end

  if cmd == "recruit" or cmd == "recruitment" then
    JGH.OpenPage("recruitment")
    return
  end

  if cmd == "craft" or cmd == "crafters" then
    JGH.OpenPage("crafters")
    if arg ~= "" then JGH.UI.CraftersSearch(arg) end
    return
  end

  if cmd == "raids" or cmd == "raid" then
    JGH.OpenPage("raids")
    return
  end

  if cmd == "roll" then
    -- Item links keep their case, so they come from the raw text.
    local link = raw:match("(|c.-|Hitem:.-|h.-|h|r)")
    if link then JGH.Loot.Start(link) else JGH.Msg("Shift-click an item into the command: /jgh roll [item]") end
    return
  end

  if cmd == "itemrolltest" then
    if arg == "enable" or arg == "disable" then JGH.Loot.SetTest(arg == "enable") end
    JGH.Msg(JGH.Loot.test and "Item roll test is on: loot anything inside a planned raid and the roll panel opens, or use /jgh roll [item]. Reserves on TEMP ITEM count for whatever you loot."
      or "Item roll test is off.")
    return
  end

  if cmd == "clock" then
    if arg == "12" or arg == "24" then JGH.Raids.SetClock(tonumber(arg)) end
    JGH.Msg("Raid times use a " .. (JGH.Raids.Use12h() and "12" or "24") .. " hour clock.")
    return
  end

  if cmd == "dings" or cmd == "ding" then
    if arg == "on" or arg == "off" then
      JGH.Dings.SetEnabled(arg == "on")
    elseif arg == "preview" then
      JGH.UI.PreviewDing()
      return
    elseif arg == "reset" then
      JGH.UI.ResetToastPosition()
      JGH.Msg("Popups are back in their default spot.")
      return
    end
    JGH.Msg("Guild level-up popups are " .. (JGH.Dings.Enabled() and "on." or "off."))
    return
  end

  if cmd == "help" or cmd == "?" then
    PrintHelp()
    return
  end

  if cmd == "whispers" then
    JGH.OpenPage("recruitment", JGH.TAB_WHISPERS)
    return
  end

  if cmd == "minimap" then
    local shown = JGH.ToggleMinimapButton()
    JGH.Msg("Minimap icon " .. (shown and "shown." or "hidden."))
    return
  end

  if cmd == "map" then
    local which, value = arg:match("^(%a+)%s+(%a+)$")
    if not which then value = arg end
    if value == "on" or value == "off" then
      local on = value == "on"
      if which == "minimap" then
        JGH.Map.SetMinimap(on)
      elseif not which then
        JGH.Map.SetShowing(on)
      end
    end
    JGH.Msg(("Guild members on the map: %s. On the minimap: %s."):format(
      JGH.Map.Showing() and "on" or "off", JGH.Map.MinimapShowing() and "on" or "off"))
    return
  end

  if cmd == "invite" then
    if arg == "chat" or arg == "copy" then
      JGH.DB().inviteMode = arg
      JGH.Msg(arg == "chat" and "Invite opens chat with /ginvite ready." or "Invite opens a copy box with /ginvite.")
    else
      JGH.Msg("Invite mode: " .. (JGH.DB().inviteMode or "copy") .. ". Use /jgh invite chat or /jgh invite copy.")
    end
    return
  end

  if cmd == "sync" then
    if arg == "on" or arg == "off" then
      JGH.DB().sync = arg == "on"
      if arg == "on" then JGH.Sync.Hello() end
    end
    JGH.Msg("Officer sync is " .. (JGH.DB().sync and "on." or "off."))
    return
  end

  if cmd == "days" then
    local n = tonumber(arg)
    if n and n >= 0 and n <= 60 then
      JGH.DB().hideDays = math.floor(n)
      JGH.Fire("ContactsChanged")
    end
    JGH.Msg("Contacted players stay hidden for " .. (JGH.DB().hideDays or 3) .. " days.")
    return
  end

  if cmd == "resetcontacts" then
    JGH.Contacts.ResetAll()
    JGH.Msg("Contact history cleared for this guild.")
    return
  end

  PrintHelp()
end
