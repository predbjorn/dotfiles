# https://github.com/webpro/dotfiles/blob/master/system/.alias

# # Git
alias commit="git add . && git commit -m"
alias gd="git diff"
alias gitclearall="git branch | grep -v "master" | xargs git branch -D"

### Delete all local branches that have been merged to main branch
# alias gitclear="git branch --merged | egrep -v "(^\*|master|main|dev)" | xargs git branch -d"
# alias gst="git status"
# alias gc="git checkout"
# alias gl="git log --oneline --decorate --color"

# cd 
alias _hack="cd ~/Hacking"
alias _hrn="cd ~/Hacking/ReactNative/helseoversikt_rn"
alias _project="cd ~/Hacking/projects"
alias _go="cd ~/Hacking/projects/goRaid"
alias hrn="cd ~/Hacking/ReactNative/helseoversikt_rn && code . && rn"
alias _dot="cd ~/.dotfiles"
alias dot="cd ~/.dotfiles && code ."
alias portal="osascript ~/.dotfiles/AppleScripts/portal.applescript"
alias _portal="cd ~/Hacking/React/partnerPortal/"
alias tren_web="osascript ~/.dotfiles/AppleScripts/tren.applescript"
alias tren="cd ~/Hacking/projects/tren && code ."
alias tren_server="cd ~/Hacking/projects/tren/tren_server && code ."
alias tren_app="cd ~/Hacking/projects/tren/tren_app && code ."
alias fouweb="osascript ~/.dotfiles/AppleScripts/fou.applescript"
alias _fouweb="cd ~/Hacking/projects/foundation/found_web"
alias _fou="cd ~/Hacking/projects/foundation/foundation"

alias stop="killall node"
alias _e="emulator -avd Pixel4"
alias logcat="logcat-ui"
alias devmenu="adb shell input keyevent 82"
alias xbuild="pkill XCBBuildService"

alias npmrs="npm start -- --reset-cache"

alias is="npm i && cd ios && bundle exec pod install && cd .. && _done && npm start"
alias isf="npm i --force && cd ios && bundle exec pod install && cd .. && _done && npm start"

alias rni="npm i && cd ios && bundle exec pod install && cd .. && afplay /Users/predbjorn/.dotfiles/resources/Zelda_puzzle_OOT.aiff"
alias rnif="npm i -f && cd ios && bundle exec pod install && cd .. && afplay /Users/predbjorn/.dotfiles/resources/Zelda_puzzle_OOT.aiff"
alias podi="cd ios && bundle exec pod install && cd .. && afplay /Users/predbjorn/.dotfiles/resources/Zelda_puzzle_OOT.aiff"
alias build="cd android &&  ./gradlew bundleRelease && open ./app/build/outputs/bundle/release/ && cd .."
alias openr="open ./app/build/outputs/bundle/release/"
alias clean="rm -rf node_modules package-lock.lock && npm cache clean --force && npm install"

alias emu="lsof -ti tcp:9000 | xargs kill -9 && lsof -ti tcp:3000 | xargs kill -9 && lsof -ti tcp:8080 | xargs kill -9 && lsof -ti tcp:8085 | xargs kill -9 | firebase emulators:start"

alias trenpg="psql $TREN_POSTGRESQL_STRING"
alias trenpg="psql -h ec2-52-50-161-219.eu-west-1.compute.amazonaws.com -U iuzlyhwhwyrrin -d d8adj60pvvngoe" # 75ac98c9c9f48b1b0173c2b0b2f785fdf3df93c643f083df93a9b781d97c6156
alias _trenpg='psql -p5432 "predbjorn"'
alias _trenpg_docker='psql -h localhost -U postgres -d postgres'
alias _trenpg='psql -p5432 "predbjorn"'

alias caff='caffeinate'
alias hour='caffeinate -t 3600'

alias countfiles='find . -type f -name "*.js" -not -path "./node_modules/*" | wc -l'




# alias hrn_dsym="~/Hacking/ReactNative/helseoversikt_rn/ios/Pods/FirebaseCrashlytics/upload-symbols -gsp /Users/predbjorn/Hacking/ReactNative/helseoversikt_rn/ios/AppConfig/Firebase/GoogleService-Info-prod.plist -p ios " 
# add dsym file after this :)  