# https://github.com/webpro/dotfiles/blob/master/system/.alias

# # Git
alias commit="git add . && git commit -m"
alias gd="git diff"
# alias gst="git status"
# alias gc="git checkout"
# alias gl="git log --oneline --decorate --color"

# Brew
alias cask="brew --cask"

# APPS
# alias chrome="open -a ~/Applications/Google\ Chrome.app"
# Open iOS Simulator
# alias ios="open /Applications/Xcode.app/Contents/Developer/Applications/iOS\ Simulator.app"

# cd 
alias _hrn="cd ~/Hacking/ReactNative/helseoversikt_rn"
alias hrn="cd ~/Hacking/ReactNative/helseoversikt_rn && code . && rn"
alias _dot="cd ~/.dotfiles"
alias dot="cd ~/.dotfiles && code ."
alias portal="osascript ~/.dotfiles/AppleScripts/portal.applescript"
alias _portal="cd ~/Hacking/React/partnerPortal/"
alias tren="osascript ~/.dotfiles/AppleScripts/tren.applescript"
alias _tren="cd ~/Hacking/projects/tren/"
alias fou="osascript ~/.dotfiles/AppleScripts/fou.applescript"
alias _fou="cd ~/Hacking/projects/foundation/found_web"

alias stop="killall node"
alias _e="emulator -avd Pixel4"
alias logcat="logcat-ui"
alias devmenu="adb shell input keyevent 82"

alias npmrs="npm start -- --reset-cache"

alias podi="cd ios &&  pod install && cd .."
alias build="cd android &&  ./gradlew bundleRelease && open ./app/build/outputs/bundle/release/ && cd .."
alias openr="open ./app/build/outputs/bundle/release/"
alias clean="rm -rf node_modules package-lock.lock && npm cache clean --force && npm install"

alias gitclear="git branch | grep -v "master" | xargs git branch -D"

alias _done="afplay /System/Library/Sounds/Basso.aiff"