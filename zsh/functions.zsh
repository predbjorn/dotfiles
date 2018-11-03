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
  # Update npm & packages
  npm install npm -g
  npm update -g
  # Update Ruby & gems
  gem update —system
  gem update
  # Update android
  sdkmanager update sdk --no-ui
}

hacktime (){
  # open -a /Applications/Google\ Chrome.app
  open -a /Applications/Xcode.app
  open -a /Applications/Visual\ Studio\ Code.app
  open -a /Applications/Slack.app
  open -a /Applications/Spotify.app
  open -a /Applications/React Native Debugger.app
  open -a /Applications/Reactotron.app
  open -a /Applications/Dash.app
  open -a /Applications/Evernote.app
}