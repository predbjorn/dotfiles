# finicky
cp $DOTFILES/.config/finicky.js /Users/predbjorn/.finicky.js 

mkdir -p $XDG_CONFIG_HOME/skhd
# rm -rf $XDG_CONFIG_HOME/skhd/skhdrc
# ln -s $DOTFILES/.config/skhdrc $XDG_CONFIG_HOME/skhd/skhdrc
yes | cp $DOTFILES/.config/skhdrc $XDG_CONFIG_HOME/skhd/skhdrc
chmod +x $XDG_CONFIG_HOME/skhd/skhdrc
skhd --start-service

rm -rf ~/.config/karabiner/karabinder.json
ln -s $DOTFILES/.config/karabinder.json ~/.config/karabiner/karabinder.json

# yabai 
mkdir -p $XDG_CONFIG_HOME/yabai
rm -rf $XDG_CONFIG_HOME/yabai/yabairc
ln -s $DOTFILES/.config/yabairc $XDG_CONFIG_HOME/yabai/yabairc
chmod +x $XDG_CONFIG_HOME/yabai/yabairc



# brew tap FelixKratz/formulae
# brew install borders

mkdir -p $XDG_CONFIG_HOME/borders
rm -rf $XDG_CONFIG_HOME/borders/bordersrc
ln -s $DOTFILES/.config/borders/bordersrc $XDG_CONFIG_HOME/borders/bordersrc
chmod +x $XDG_CONFIG_HOME/borders/bordersrc



echo "sketchybar Installing Dependencies"
curl -L https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v1.0.23/sketchybar-app-font.ttf -o $HOME/Library/Fonts/sketchybar-app-font.ttf
echo "sketchybar Cloning Config"
cp -R $DOTFILES/.config/sketchybar $HOME/.config/sketchybar

## STYLES
# https://github.com/catppuccin/catppuccin?tab=readme-ov-file


brew services restart sketchybar
yabai --start-service