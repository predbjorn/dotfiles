mkdir -p $XDG_CONFIG_HOME/skhd
# rm -rf $XDG_CONFIG_HOME/skhd/skhdrc
# ln -s $DOTFILES/.config/skhdrc $XDG_CONFIG_HOME/skhd/skhdrc
yes | cp $DOTFILES/.config/skhdrc $XDG_CONFIG_HOME/skhd/skhdrc
chmod +x $XDG_CONFIG_HOME/skhd/skhdrc
skhd --start-service

rm -rf ~/.config/karabiner/karabinder.json
ln -s $DOTFILES/.config/karabinder.json ~/.config/karabiner/karabinder.json
