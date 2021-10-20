tell application "iTerm"
	tell current window
		 -- create a tab for background stuff
        tell current session
            write text "cd ~/Hacking/projects/foundation/found_web/"
            write text "npm run-script watch"
        end tell
		-- create tab to run aioc server
        create tab with default profile
        tell current session
            write text "cd ~/Hacking/projects/foundation/found_web/"
		-- split tab vertically to run server
		split vertically with default profile
            write text "code ."
            write text "npm start"
        end tell
		 tell last session of last tab
            write text "cd ~/Hacking/projects/foundation/found_sanity/"
            write text "code ."
        end tell
	end tell
end tell