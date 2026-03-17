#!/bin/bash


# If script is run by skhd (not running with zsh)
HOME=${HOME:-'/Users/predbjorn'}
DOTFILES=${DOTFILES:-"$HOME/.DOTFILES"}
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}

#THEMES
# mkdir -p $HOME/.warp/themes/
# cp $DOTFILES/themes/catppuccin_mocha.yml $HOME/.warp/themes/

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


chmod +x $DOTFILES/bin/focus_window_wrapper.sh
chmod +x $DOTFILES/script/windowarr.sh

yabai --start-service

# sketchybar
rm -rf $XDG_CONFIG_HOME/sketchybar
cp -r $DOTFILES/.config/sketchybar $XDG_CONFIG_HOME/sketchybar
chmod -R +x $XDG_CONFIG_HOME/sketchybar
brew services restart sketchybar