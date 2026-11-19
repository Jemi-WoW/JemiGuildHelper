local _, ZR = ...

SLASH_ZUGZUGREBORN1 = "/zugzug"
SLASH_ZUGZUGREBORN2 = "/zr"

local function PrintHelp()
  ZR.Msg("Commands:")
  ZR.Msg("  |cffffd100/zr|r - open the Guild window page where you left off")
  ZR.Msg("  |cffffd100/zr recruit|r - open Recruitment")
  ZR.Msg("  |cffffd100/zr whispers|r - open the Whispers tab")
  ZR.Msg("  |cffffd100/zr craft <item>|r - find who in the guild can craft it")
  ZR.Msg("  |cffffd100/zr raids|r - open raid sign-ups")
  ZR.Msg("  |cffffd100/zr clock 12|r or |cffffd10024|r - how raid times are shown")
  ZR.Msg("  |cffffd100/zr roll [item]|r - start a roll for an item (raid leader, assistant or master looter)")
  ZR.Msg("  |cffffd100/zr dings on|r or |cffffd100off|r - guild level-up popups (|cffffd100preview|r to place them, |cffffd100reset|r to move them back)")
  ZR.Msg("  |cffffd100/zr minimap|r - show or hide the minimap icon")
  ZR.Msg("  |cffffd100/zr map on|r or |cffffd100off|r - guild members on the world map")
  ZR.Msg("  |cffffd100/zr map share on|r or |cffffd100off|r - share your own position with the guild")
  ZR.Msg("  |cffffd100/zr map minimap on|r or |cffffd100off|r - guild members on the minimap")
  ZR.Msg("  |cffffd100/zr invite chat|r or |cffffd100copy|r - how Invite hands you /ginvite")
  ZR.Msg("  |cffffd100/zr sync on|r or |cffffd100off|r - share contacts with other officers")
  ZR.Msg("  |cffffd100/zr days <n>|r - hide contacted players for n days (now " .. (ZR.DB().hideDays or 3) .. ")")
  ZR.Msg("  |cffffd100/zr resetcontacts|r - forget every whisper, invite and decline")
end

SlashCmdList["ZUGZUGREBORN"] = function(msg)
  local raw = msg or ""
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")

  if cmd == "" then
    ZR.OpenPage()
    return
  end

  if cmd == "recruit" or cmd == "recruitment" then
    ZR.OpenPage("recruitment")
    return
  end

  if cmd == "craft" or cmd == "crafters" then
    ZR.OpenPage("crafters")
    if arg ~= "" then ZR.UI.CraftersSearch(arg) end
    return
  end

  if cmd == "raids" or cmd == "raid" then
    ZR.OpenPage("raids")
    return
  end

  if cmd == "roll" then
    -- Item links keep their case, so they come from the raw text.
    local link = raw:match("(|c.-|Hitem:.-|h.-|h|r)")
    if link then ZR.Loot.Start(link) else ZR.Msg("Shift-click an item into the command: /zr roll [item]") end
    return
  end

  if cmd == "itemrolltest" then
    if arg == "enable" or arg == "disable" then ZR.Loot.SetTest(arg == "enable") end
    ZR.Msg(ZR.Loot.test and "Item roll test is on: loot anything inside a planned raid and the roll panel opens, or use /zr roll [item]. Reserves on TEMP ITEM count for whatever you loot."
      or "Item roll test is off.")
    return
  end

  if cmd == "clock" then
    if arg == "12" or arg == "24" then ZR.Raids.SetClock(tonumber(arg)) end
    ZR.Msg("Raid times use a " .. (ZR.Raids.Use12h() and "12" or "24") .. " hour clock.")
    return
  end

  if cmd == "dings" or cmd == "ding" then
    if arg == "on" or arg == "off" then
      ZR.Dings.SetEnabled(arg == "on")
    elseif arg == "preview" then
      ZR.UI.PreviewDing()
      return
    elseif arg == "reset" then
      ZR.UI.ResetToastPosition()
      ZR.Msg("Popups are back in their default spot.")
      return
    end
    ZR.Msg("Guild level-up popups are " .. (ZR.Dings.Enabled() and "on." or "off."))
    return
  end

  if cmd == "help" or cmd == "?" then
    PrintHelp()
    return
  end

  if cmd == "whispers" then
    ZR.OpenPage("recruitment", ZR.TAB_WHISPERS)
    return
  end

  if cmd == "minimap" then
    local shown = ZR.ToggleMinimapButton()
    ZR.Msg("Minimap icon " .. (shown and "shown." or "hidden."))
    return
  end

  if cmd == "map" then
    local which, value = arg:match("^(%a+)%s+(%a+)$")
    if not which then value = arg end
    if value == "on" or value == "off" then
      local on = value == "on"
      if which == "share" then
        ZR.Map.SetSharing(on)
      elseif which == "minimap" then
        ZR.Map.SetMinimap(on)
      elseif not which then
        ZR.Map.SetShowing(on)
      end
    end
    ZR.Msg(("Guild members on the map: %s. On the minimap: %s. Sharing your position: %s."):format(
      ZR.Map.Showing() and "on" or "off", ZR.Map.MinimapShowing() and "on" or "off", ZR.Map.Sharing() and "on" or "off"))
    return
  end

  if cmd == "invite" then
    if arg == "chat" or arg == "copy" then
      ZR.DB().inviteMode = arg
      ZR.Msg(arg == "chat" and "Invite opens chat with /ginvite ready." or "Invite opens a copy box with /ginvite.")
    else
      ZR.Msg("Invite mode: " .. (ZR.DB().inviteMode or "copy") .. ". Use /zr invite chat or /zr invite copy.")
    end
    return
  end

  if cmd == "sync" then
    if arg == "on" or arg == "off" then
      ZR.DB().sync = arg == "on"
      if arg == "on" then ZR.Sync.Hello() end
    end
    ZR.Msg("Officer sync is " .. (ZR.DB().sync and "on." or "off."))
    return
  end

  if cmd == "days" then
    local n = tonumber(arg)
    if n and n >= 0 and n <= 60 then
      ZR.DB().hideDays = math.floor(n)
      ZR.Fire("ContactsChanged")
    end
    ZR.Msg("Contacted players stay hidden for " .. (ZR.DB().hideDays or 3) .. " days.")
    return
  end

  if cmd == "resetcontacts" then
    ZR.Contacts.ResetAll()
    ZR.Msg("Contact history cleared for this guild.")
    return
  end

  PrintHelp()
end
