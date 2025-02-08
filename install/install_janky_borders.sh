# brew tap FelixKratz/formulae
# brew install borders

mkdir -p $XDG_CONFIG_HOME/borders
rm -rf $XDG_CONFIG_HOME/borders/bordersrc
ln -s $DOTFILES/.config/borders/bordersrc $XDG_CONFIG_HOME/borders/bordersrc
chmod +x $XDG_CONFIG_HOME/borders/bordersrc
