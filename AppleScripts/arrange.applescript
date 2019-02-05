# arrange.scpt
#
# set dimensions and position of commonly used applications
# depending on whether one or two monitors are attached
#
# to add an application, find its bounds with both one and two
# displays connected:
#
# tell application "System Events"
#   tell application "ApplicationName"
#     get bounds of window 1
#   end tell
# end tell

# get frontmost application so we can bring it back to frontmost 
# on completion of script
tell application "System Events"
  set focus to name of the first process whose frontmost is true
end tell

# get width of desktop
tell application "Finder"
  set bnds to bounds of window of desktop
  set wide to item 3 of bnds
end tell

set resolutions to {}
repeat with p in paragraphs of Â
    (do shell script "system_profiler SPDisplaysDataType | awk '/Resolution:/{ printf \"%s %s %s\\n\", $2, $4, ($5 == \"Retina\" ? 2 : 1) }'")
    set resolutions to resolutions & {{word 1 of p as number, word 2 of p as number, word 3 of p as number}}
end repeat

get resolutions

# find out number of displays connected based on screen width
# 1440 is the width of a 15 inch MacBook Pro. change this 
# based on your screen size. 
if wide is equal to 1440 then
  set displaynum to "onedisp"
else
  set displaynum to "twodisp"
end if

# make the smaller, center-most terminal window frontmost
# i always have two terminal windows open - this assures
# the correct windows are resized and moved. 
tell application "System Events"
  set if_running to (exists process "Terminal")
  if if_running then
    tell application "Terminal"
      activate
      set bnds_one to get bounds of window 1
      set wide_one to item 3 of bnds_one
      set bnds_two to get bounds of window 2
      set wide_two to item 3 of bnds_two
      if wide_one is greater than wide_two then
        tell application "System Events"
          keystroke "`" using command down
        end tell
      end if
    end tell
  end if
end tell

tell application "System Events"
  set if_running to (exists process "Terminal")
  if if_running then
    if displaynum is equal to "onedisp" then
      tell application "Terminal"
        activate
        try
          set bounds of window 1 to {286, 176, 1052, 668}
          set bounds of window 2 to {323, 215, 1425, 889}
        end try
      end tell
    else
      tell application "Terminal"
        activate
        try
          set bounds of window 1 to {2249, -467, 2868, -101}
          set bounds of window 2 to {2249, -86, 3351, 588}
        end try
      end tell
    end if
  end if
end tell

# resize the rest of the applications that are usually open. 
# note the "try" commands - this is a failsafe in addition
# to 'exists process "foo"' so the script doesn't choke if the 
# application is not running. 

tell application "System Events"
  set if_running to (exists process "TextMate")
  if if_running then
    if displaynum is equal to "onedisp" then
      tell application "TextMate"
        activate
        try
          set bounds of window 1 to {18, 34, 567, 885}
        end try
      end tell
    else
      tell application "TextMate"
        activate
        try
          set bounds of window 1 to {1450, -466, 2239, 582}
        end try
      end tell
    end if
  end if
end tell

tell application "System Events"
  set if_running to (exists process "Google Chrome Canary")
  if if_running then
    if displaynum is equal to "onedisp" then
      tell application "Google Chrome Canary"
        activate
        try
          set bounds of window 1 to {196, 55, 1398, 811}
        end try
      end tell
    else
      tell application "Google Chrome Canary"
        activate
        try
          set bounds of window 1 to {0, 22, 1440, 899}
        end try
      end tell
    end if
  end if
end tell

tell application "System Events"
  set if_running to (exists process "iTunes")
  if if_running then
    if displaynum is equal to "onedisp" then
      tell application "iTunes"
        activate
        try
          set bounds of window 1 to {90, 103, 1239, 833}
        end try
      end tell
    else
      tell application "iTunes"
        activate
        try
          set bounds of window 1 to {85, 135, 1234, 865}
        end try
      end tell
    end if
  end if
end tell

tell application "System Events"
  set if_running to (exists process "Transmission")
  if if_running then
    if displaynum is equal to "onedisp" then
      tell application "Transmission"
        activate
        try
          set bounds of window 1 to {962, 36, 1424, 404}
        end try
      end tell
    else
      tell application "Transmission"
        activate
        try
          set bounds of window 1 to {2882, -470, 3344, -102}
        end try
      end tell
    end if
  end if
end tell

# tweetie is old and incompatible with the other functions.
tell application "System Events"
  tell process "Tweetie"
    activate
    try
      set size of window 1 to {355, 878}
    end try
    try
      set position of window 1 to {1, 23}
    end try
  end tell
end tell

# set frontmost application back
tell application focus
  activate
end tell