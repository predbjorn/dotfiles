echo "Installing Dependencies"
brew install --cask sf-symbols
brew install jq
brew install gh
brew install switchaudio-osx
brew tap FelixKratz/formulae
brew install sketchybar
curl -L https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v1.0.23/sketchybar-app-font.ttf -o $HOME/Library/Fonts/sketchybar-app-font.ttf

echo "Cloning Config"
mv $HOME/.config/sketchybar $HOME/.config/sketchybar_backup
cp -R $DOTFILES/.config/sketchybar $HOME/.config/sketchybar
brew services restart sketchybar

# mkdir -p ~/.config/sketchybar/plugins
# cp $(brew --prefix)/share/sketchybar/examples/sketchybarrc ~/.config/sketchybar/sketchybarrc
# cp -r $(brew --prefix)/share/sketchybar/examples/plugins/ ~/.config/sketchybar/plugins/
# https://felixkratz.github.io/SketchyBar/setup

## STYLES
# https://github.com/catppuccin/catppuccin?tab=readme-ov-file
