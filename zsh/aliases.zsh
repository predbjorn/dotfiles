# https://github.com/webpro/dotfiles/blob/master/system/.alias

# # Git
alias commit="git add . && git commit -m"
alias gd="git diff"
alias gitclear="git branch | grep -v "master" | xargs git branch -D"
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
alias fouweb="osascript ~/.dotfiles/AppleScripts/fou.applescript"
alias _fouweb="cd ~/Hacking/projects/foundation/found_web"
alias _fou="cd ~/Hacking/projects/foundation/foundation"

alias stop="killall node"
alias _e="emulator -avd Pixel4"
alias logcat="logcat-ui"
alias devmenu="adb shell input keyevent 82"

alias npmrs="npm start -- --reset-cache"

alias rni="npm i && cd ios && pod install && cd .. && afplay /Users/predbjorn/.dotfiles/resources/Zelda_puzzle_OOT.aiff"
alias podi="cd ios && pod install && cd .."
alias build="cd android &&  ./gradlew bundleRelease && open ./app/build/outputs/bundle/release/ && cd .."
alias openr="open ./app/build/outputs/bundle/release/"
alias clean="rm -rf node_modules package-lock.lock && npm cache clean --force && npm install"



# alias _done="afplay /System/Library/Sounds/Basso.aiff"
alias _done="afplay /Users/predbjorn/.dotfiles/resources/Zelda_puzzle_OOT.aiff"

alias hrn_dsym="~/Hacking/ReactNative/helseoversikt_rn/ios/Pods/FirebaseCrashlytics/upload-symbols -gsp /Users/predbjorn/Hacking/ReactNative/helseoversikt_rn/ios/AppConfig/Firebase/GoogleService-Info-prod.plist -p ios " 
# add dsym file after this :)  