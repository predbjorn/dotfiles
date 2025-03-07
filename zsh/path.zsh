
export GOOGLE_APPLICATION_CREDENTIALS="/usr/local/devConfig/firebase/helseoversiktdev.json"
# export GOOGLE_APPLICATION_CREDENTIALS="/usr/local/devConfig/firebase/helseoversiktprod.json:$GOOGLE_APPLICATION_CREDENTIALS"
# export GOOGLE_APPLICATION_CREDENTIALS="/usr/local/devConfig/firebase/helseoversiktprod.json"

export BREW_HOME="/usr/local/opt/"
eval "$(/opt/homebrew/bin/brew shellenv)"

export CASK_HOME="/usr/local/share/"



export XDG_CONFIG_HOME="$HOME/.config"
export DOTFILES="$HOME/.dotfiles"

# RUBY AND GEMS
export GEM_HOME="$HOME/.gem"
export PATH="$GEM_HOME/bin:$PATH"
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

# Jenv
# Run brew info java
# Then jenv add PATH_TO_JAVA_VERSION
export PATH="$HOME/.jenv/bin:$PATH"
# eval "$(jenv init -)"


# Export nvm completion settings for zsh-nvm plugin
export NVM_DIR="$HOME/.nvm"
export NVM_COMPLETION=true

# pyenv (python)
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"

# CODE vscode
# Add Visual Studio Code (code)
export PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:$PATH"

#Java & Android
export JAVA_HOMES="/Library/Java/JavaVirtualMachines/"
# export JAVA_HOME="`jenv javahome`"
export ANT_HOME="/usr/local/opt/ant"
export MAVEN_HOME="/usr/local/opt/maven"
export GRADLE_HOME="/usr/local/opt/gradle"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

export PATH="$ANT_HOME/bin:$PATH"
export PATH="$MAVEN_HOME/bin:$PATH"
export PATH="$GRADLE_HOME/bin:$PATH"
export PATH="$ANDROID_HOME/tools:$PATH"
export PATH="$ANDROID_HOME/tools/bin:$PATH"
export PATH="$ANDROID_HOME/emulator:$PATH"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
# export PATH="$ANDROID_HOME/build-tools/30.0.3:$PATH"
# If you want the latest version of the build-tools and not the most recently installed try this
export PATH=$ANDROID_HOME/build-tools/$(ls $ANDROID_HOME/build-tools | sort | tail -1):$PATH


export CLOUDSDK_PYTHON=$(which python3.11)
source "$(brew --prefix)/share/google-cloud-sdk/path.zsh.inc"
source "$(brew --prefix)/share/google-cloud-sdk/completion.zsh.inc"

export TREN_POSTGRESQL_STRING="postgres://iuzlyhwhwyrrin:75ac98c9c9f48b1b0173c2b0b2f785fdf3df93c643f083df93a9b781d97c6156@ec2-52-50-161-219.eu-west-1.compute.amazonaws.com:5432/d8adj60pvvngoe"
# export DEBUG=app:*

# wget
# A CA file has been bootstrapped using certificates from the SystemRoots
# keychain. To add additional certificates (e.g. the certificates added in
# the System keychain), place .pem files in
#   /usr/local/etc/openssl/certs

# and run
#   /usr/local/opt/openssl/bin/c_rehash

# openssl is keg-only, which means it was not symlinked into /usr/local,
# because Apple has deprecated use of OpenSSL in favor of its own TLS and crypto libraries.

# If you need to have openssl first in your PATH run:
# echo 'export PATH="/usr/local/opt/openssl/bin:$PATH"' >> ~/.zshrc

# For compilers to find openssl you may need to set:
#   export LDFLAGS="-L/usr/local/opt/openssl/lib"
#   export CPPFLAGS="-I/usr/local/opt/openssl/include"


export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8


## Commands for postgres
# sudo mkdir -p /etc/paths.d &&
# echo /Applications/Postgres.app/Contents/Versions/latest/bin | sudo tee /etc/paths.d/postgresapp