# Create a new directory and enter it
function mk() {
  mkdir -p "$@" && cd "$@"
}

# Open man page as PDF
function manpdf() {
 man -t "${1}" | open -f -a /Applications/Preview.app/
}

update () {
  # Update App Store apps
  sudo softwareupdate -i -a
  # Update Homebrew (Cask) & packages
  brew update
  brew upgrade
  brew cask upgrade
  mas upgrade
  # Update npm & packages
  npm install npm -g
  npm update -g
  # Update Ruby & gems
  gem update —system
  gem update
  # Update android
#   sdkmanager update sdk --no-ui
}

hacktime (){
  # open -a /Applications/Google\ Chrome.app
	open -a /Applications/Xcode.app
	open -a /Applications/Visual\ Studio\ Code.app
	open -a /Applications/Slack.app
	open -a /Applications/Spotify.app
	open -a /Applications/React\ Native\ Debugger.app
	open -a /Applications/Safari.app
	open -a /Applications/SourceTree.app
#   open -a /Applications/TogglDesktop.app
#   open -a /Applications/Mail.app
#   open -a /Applications/Evernote.app
	osascript ~/.dotfiles/AppleScripts/hacktime.applescript
}

hacktime2 (){
  # open -a /Applications/Google\ Chrome.app
  open -a /Applications/Xcode.app
  open -a /Applications/Visual\ Studio\ Code.app
  open -a /Applications/Slack.app
  open -a /Applications/Spotify.app
  open -a /Applications/React\ Native\ Debugger.app
#   open -a /Applications/Evernote.app
}

rn (){
  	open -a /Applications/React\ Native\ Debugger.app
  	open -a /Applications/Xcode.app
#   open -a /Applications/Evernote.app
}

_done (){
	# afplay $DOTFILES/resources/zelda.wav
	afplay $DOTFILES/resources/randomstarwars/$(jot -r 1 1 5).wav
}

_d (){
	afplay $DOTFILES/resources/randomstarwars/$(jot -r 1 1 5).wav
}

mvp (){
    dir="$2" # Include a / at the end to indicate directory (not filename)
    tmp="$2"; tmp="${tmp: -1}"
    [ "$tmp" != "/" ] && dir="$(dirname "$2")"
    [ -a "$dir" ] ||
    mkdir -p "$dir" &&
    mv "$@"
}



check () { ## For checking unused dependencies
	cd $DIRNAME
	FILES=$(mktemp)
	PACKAGES=$(mktemp)
	# use fd
	# https://github.com/sharkdp/fd

	function _check {
		cat package.json \
			| jq "{} + .$1 | keys" \
			| sed -n 's/.*"\(.*\)".*/\1/p' > $PACKAGES
		echo "--------------------------"
		echo "Checking $1..."
		fd '(js|ts|json)$' -t f > $FILES
		while read PACKAGE
		do
			if [ -d "node_modules/${PACKAGE}" ]; then
				fd  -t f '(js|ts|json)$' node_modules/${PACKAGE} >> $FILES
			fi
			RES=$(cat $FILES | xargs -I {} egrep -i "(import|require|loader|plugins|${PACKAGE}).*['\"](${PACKAGE}|.?\d+)[\"']" '{}' | wc -l)

			if [ $RES = 0 ]
			then
				echo -e "UNUSED\t\t $PACKAGE"
			else
				echo -e "USED ($RES)\t $PACKAGE"
			fi
		done < $PACKAGES
	}
	
	_check "dependencies"
	_check "devDependencies"
	_check "peerDependencies"
}
