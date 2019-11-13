on getResolutions()
	set resolutions to {}
	repeat with p in paragraphs of Â
		(do shell script "system_profiler SPDisplaysDataType | awk '/Resolution:/{ printf \"%s %s\\n\", $2, $4 }'")
		set resolutions to resolutions & {{word 1 of p as number, word 2 of p as number}}
	end repeat
end getResolutions

set mbFull to {1680, 1030}
set mbscreen to {0, 0}
set fullhdScreen to false
set viewSonic to false

repeat with i from 1 to count of getResolutions()
	set screen to item i of getResolutions()
	if item 1 of screen = 3840 then
		set viewSonic to true
		set mbscreen to {1070, 1600}
	else if item 1 of screen = 1980 then
		set fullhdScreen to true
	end if
end repeat



set SlackSize to mbFull
set SlackPosition to mbscreen
set ReactSize to {840, 1030}
set ReactPosition to mbscreen
set XcodeSize to mbFull
set XcodePosition to mbscreen
set CodeSize to mbFull
set CodePosition to mbscreen
set SpotifySize to mbFull
set SpotifyPosition to mbscreen
set SafariSize to mbFull
set SafariPosition to mbscreen
-- set MailSize to mbFull
-- set MailPosition to mbscreen
-- set TogglSize to {400, 600}
-- set TogglPosition to {1280, 0}

if viewSonic then --{3840x1600} + {2880, 1800 (1680, 1030)}
	set vsleft to {0, 0}
	set vsCenter to {1280, 0}
	set vsRight to {2560, 0}
	set colSize to {1280, 1600}
	set halfColSize to {1280, 800}
	
	set SlackSize to halfColSize
	set SlackPosition to vsRight
	set ReactSize to colSize
	set ReactPosition to vsleft
	set XcodeSize to mbFull
	set XcodePosition to mbscreen
	set CodeSize to mbFull
	set CodePosition to mbscreen
	set SpotifySize to mbFull
	set SpotifyPosition to mbscreen
	set SafariSize to colSize
	set SafariPosition to vsCenter
	set TogglSize to {400, 600}
	set TogglPosition to {3440, 1000}
	set MailSize to halfColSize
	set MailPosition to {2560, 800}
	set iTermSize to colSize
	set iTermPosition to vsRight
end if




tell application "System Events"
	tell process "Slack"
		set frontWindow to first window
		set position of frontWindow to SlackPosition
		set size of frontWindow to SlackSize
	end tell
	tell process "Xcode"
		set frontWindow to first window
		set position of frontWindow to XcodePosition
		set size of frontWindow to XcodeSize
	end tell
	-- tell process "TogglDesktop"
	-- 	set frontWindow to first window
	-- 	set position of frontWindow to TogglPosition
	-- 	set size of frontWindow to TogglSize
	-- end tell
	tell process "Sourcetree"
		set frontWindow to first window
		set position of frontWindow to iTermPosition
		set size of frontWindow to iTermSize
	end tell
	tell process "iTerm2"
		set frontWindow to first window
		set position of frontWindow to iTermPosition
		set size of frontWindow to iTermSize
	end tell
	tell process "Visual Studio Code"
	set frontWindow to first window
		set position of frontWindow to CodePosition
		set size of frontWindow to CodeSize
	end tell
	tell process "Spotify"
		set frontWindow to first window
		set position of frontWindow to SpotifyPosition
		set size of frontWindow to SpotifySize
	end tell
	tell process "React Native Debugger"
		set frontWindow to first window
		set position of frontWindow to ReactPosition
		set size of frontWindow to ReactSize
	end tell
	tell process "Safari"
		set frontWindow to first window
		set position of frontWindow to SafariPosition
		set size of frontWindow to SafariSize
	end tell
	-- tell process "Zeplin"
	-- 	set frontWindow to first window
	-- 	set position of frontWindow to SafariPosition
	-- 	set size of frontWindow to SafariSize
	-- end tell
	-- tell process "Mail"
	-- 	set frontWindow to first window
	-- 	set position of frontWindow to MailPosition
	-- 	set size of frontWindow to MailSize
	-- end tell
end tell


-- tell application "System Events" to tell process "Mail" to set visible to false
-- tell application "System Events" to tell process "Slack" to set visible to false

-- tell application "Visual Studio Code" to activate
-- tell application "System Events"
-- 	keystroke "f" using {command down, control down}
-- end tell
