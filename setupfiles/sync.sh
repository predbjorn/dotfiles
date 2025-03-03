#!/bin/bash


# If script is run by skhd (not running with zsh)
home=${HOME:-'/Users/predbjorn'}
dotfiles=${DOTFILES:-"$home/.dotfiles"}
config_home=${XDG_CONFIG_HOME:-"$home/.config"}

#THEMES
mkdir -p $home/.warp/themes/
cp $dotfiles/themes/catppuccin_mocha.yml $home/.warp/themes/

# finicky
cp $dotfiles/.config/.finicky.js $home/.finicky.js 

mkdir -p $config_home/skhd
rm -rf $config_home/skhd/skhdrc 
# ln -s $dotfiles/.config/skhdrc $config_home/skhd/skhdrc
yes | cp $dotfiles/.config/skhdrc $config_home/skhd/skhdrc
chmod +x $config_home/skhd/skhdrc
skhd --start-service

rm -rf ~/.config/karabiner/karabiner.json
ln -s $dotfiles/.config/karabiner.json ~/.config/karabiner/karabiner.json

# yabai 
mkdir -p $config_home/yabai
rm -rf $config_home/yabai/yabairc
ln -s $dotfiles/.config/yabairc $config_home/yabai/yabairc
chmod +x $config_home/yabai/yabairc


echo "sketchybar Installing Dependencies"
curl -L https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v1.0.23/sketchybar-app-font.ttf -o $home/Library/Fonts/sketchybar-app-font.ttf
echo "sketchybar Cloning Config"
rm -rf $home/.config/sketchybar
cp -R $dotfiles/.config/sketchybar $home/.config/sketchybar



brew services restart sketchybar
yabai --start-service