# Install pip if not installed
if ! command -v pip &> /dev/null; then
	echo "pip not found, installing..."
	curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
	python get-pip.py
	rm get-pip.py
else
	echo "pip is already installed"
fi

# Install Python packages
pip install datetime openai requests