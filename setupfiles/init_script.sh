
if command -v python3.11 &> /dev/null
then
	chmod a+x $DOTFILES/script/setCronjobs.py
	python3.11 $DOTFILES/script/setCronjobs.py
else
	echo "python3.11 is not installed."
fi