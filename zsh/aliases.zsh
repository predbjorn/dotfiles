# https://github.com/webpro/dotfiles/blob/master/system/.alias

# # Git
alias commit="git add . && git commit -m"
alias gd="git diff"
# alias gst="git status"
# alias gc="git checkout"
# alias gl="git log --oneline --decorate --color"

# Brew
alias cask="brew cask"

# APPS
# alias chrome="open -a ~/Applications/Google\ Chrome.app"
# Open iOS Simulator
# alias ios="open /Applications/Xcode.app/Contents/Developer/Applications/iOS\ Simulator.app"

# cd 
alias _hrn="cd ~/Hacking/ReactNative/helseoversikt_rn"
alias hrn="cd ~/Hacking/ReactNative/helseoversikt_rn && code ."
alias _tren="cd ~/Hacking/ReactNative/tren"
alias tren="cd ~/Hacking/ReactNative/tren && code ."
alias _dot="cd ~/.dotfiles"
alias dot="cd ~/.dotfiles && code ."


alias _e="emulator -avd s8"
alias logcat="logcat-ui"
alias devmenu="adb shell input keyevent 82"

alias npmrs="npm start -- --reset-cache"

alias openr="open ./app/build/outputs/bundle/release/"

alias gitclear="git branch | grep -v "master" | xargs git branch -D"
