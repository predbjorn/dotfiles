
tell application "Finder"
    set windowCount to (count windows)
end tell

	get windowCount
set monitorSize to {800, 600}
set monitorPosition to {800, 2000}

set SlackSize to {2000, 600}
set SlackPosition to {1600, 1900}



	-- tell application "System Events"
	-- 	tell process "Terminal"
	-- 		set frontWindow to first window
	-- 		set position of frontWindow to monitorPosition
	-- 		set size of frontWindow to monitorSize
	-- 	end tell

	-- 	tell process "Slack"
	-- 		set frontWindow to first window
	-- 		set position of frontWindow to SlackPosition
	-- 		set size of frontWindow to SlackSize
	-- 	end tell
	-- 	tell process "Xcode"
	-- 	set frontWindow to first window
	-- 		set position of frontWindow to SlackPosition
	-- 		set size of frontWindow to SlackSize
	-- 	end tell
	-- 	tell process "Visual Studio Code"
	-- 	set frontWindow to first window
	-- 		set position of frontWindow to SlackPosition
	-- 		set size of frontWindow to SlackSize
	-- 	end tell
	-- 	tell process "Spotify"
	-- 	set frontWindow to first window
	-- 		set position of frontWindow to SlackPosition
	-- 		set size of frontWindow to SlackSize
	-- 	end tell
	-- 	tell process "React Native Debugger"
	-- 	set frontWindow to first window
	-- 		set position of frontWindow to SlackPosition
	-- 		set size of frontWindow to SlackSize
	-- 	end tell
	-- end tell
