#!/bin/bash


# If script is run by skhd (not running with zsh)
HOME=${HOME:-'/Users/predbjorn'}
DOTFILES=${DOTFILES:-"$HOME/.DOTFILES"}
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}

#THEMES
mkdir -p $HOME/.warp/themes/
cp $DOTFILES/themes/catppuccin_mocha.yml $HOME/.warp/themes/

# finicky
cp $DOTFILES/.config/.finicky.js $HOME/.finicky.js 

# skhd
mkdir -p $XDG_CONFIG_HOME/skhd
rm -rf $XDG_CONFIG_HOME/skhd/skhdrc 
# ln -s $DOTFILES/.config/skhdrc $XDG_CONFIG_HOME/skhd/skhdrc
yes | cp $DOTFILES/.config/skhdrc $XDG_CONFIG_HOME/skhd/skhdrc
chmod +x $XDG_CONFIG_HOME/skhd/skhdrc
skhd --start-service

mkdir -p ~/.config/karabiner
rm -rf ~/.config/karabiner/karabiner.json
ln -s $DOTFILES/.config/karabiner.json ~/.config/karabiner/karabiner.json

# yabai 

# stop yabai
yabai --stop-service
# upgrade yabai with homebrew (remove old service file because homebrew changes binary path)

# To upgrade: 
# yabai --uninstall-service
# brew upgrade yabai

# configure yabai
mkdir -p $XDG_CONFIG_HOME/yabai
rm -rf $XDG_CONFIG_HOME/yabai/yabairc
ln -s $DOTFILES/.config/yabairc $XDG_CONFIG_HOME/yabai/yabairc
chmod +x $XDG_CONFIG_HOME/yabai/yabairc


echo "sketchybar Installing Dependencies"
curl -L https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v1.0.23/sketchybar-app-font.ttf -o $HOME/Library/Fonts/sketchybar-app-font.ttf
echo "sketchybar Cloning Config"
rm -rf $HOME/.config/sketchybar
cp -R $DOTFILES/.config/sketchybar $HOME/.config/sketchybar

chmod +x $DOTFILES/bin/focus_window_wrapper.sh
chmod +x $DOTFILES/script/windowarr.sh

brew services restart sketchybar
yabai --start-service