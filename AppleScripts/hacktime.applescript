set theApp to "Google Chrome"
set appHeight to 1080
set appWidth to 1920

tell application "Finder"
	set screenResolution to bounds of window of desktop
end tell

set screenWidth to item 3 of screenResolution
set screenHeight to item 4 of screenResolution
-- set bnds_two to get bounds of window 2

-- get bnds_two

tell application "Finder"
    set windowCount to (count windows)
	get windowCount
    if windowCount > 0 then
        set windowBounds to bounds of window 1 --> Note the '1'
        return windowBounds
    end if
end tell

-- tell application "Slack"
-- 	activate
-- 	reopen
-- 	set yAxis to (screenHeight - appHeight) / 2 as integer
-- 	set xAxis to (screenWidth - appWidth) / 2 as integer
-- 	set the bounds of window 1 to {xAxis, yAxis, appWidth + xAxis, appHeight + yAxis}
-- end tell

set resolutions to {}
repeat with p in paragraphs of Â
    (do shell script "system_profiler SPDisplaysDataType | awk '/Resolution:/{ printf \"%s %s %s\\n\", $2, $4, ($5 == \"Retina\" ? 2 : 1) }'")
    set resolutions to resolutions & {{word 1 of p as number, word 2 of p as number, word 3 of p as number}}
end repeat

get resolutions

on getResolutions()
	set resolutions to {}
	repeat with p in paragraphs of Â
		(do shell script "system_profiler SPDisplaysDataType | awk '/Resolution:/{ printf \"%s %s\\n\", $2, $4 }'")
		set resolutions to resolutions & {{word 1 of p as number, word 2 of p as number}}
	end repeat
	# `resolutions` now contains a list of size lists;
	# e.g., with 2 displays, something like {{2560, 1440}, {1920, 1200}}
end getResolutions
get getResolutions()


tell application "System Events"
  set focus to name of the first process whose frontmost is true
end tell

# get width of desktop
tell application "Finder"
  set bnds to bounds of window of desktop
  set wide to item 3 of bnds
end tell
if wide is equal to 1440 then
  set displaynum to "onedisp"
else
  set displaynum to "twodisp"
end if

if displaynum is equal to "onedisp" then


set monitorSize to {800, 600}
set monitorPosition to {800, 2000}

	tell application "System Events"
		tell process "Terminal"
			set frontWindow to first window
			set position of frontWindow to monitorPosition
			set size of frontWindow to monitorSize
		end tell
	end tell
	tell application "System Events"
		tell process "Slack"
			set frontWindow to first window
			set position of frontWindow to monitorPosition
			set size of frontWindow to monitorSize
		end tell
	end tell
	
	-- tell application "Slack"
	-- 	activate
	-- 	reopen
	-- 	set yAxis to (screenHeight - appHeight) / 2 as integer
	-- 	set xAxis to (screenWidth - appWidth) / 2 as integer
	-- 	set the bounds of window 1 to {xAxis, yAxis, appWidth + xAxis, appHeight + yAxis}
	-- end tell
end if