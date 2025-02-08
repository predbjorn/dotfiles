
if command -v python3.11 &> /dev/null
then
	chmod a+x setCronjobs.py
	python3.11 ./setCronjobs.py
else
	echo "python3.11 is not installed."
fi