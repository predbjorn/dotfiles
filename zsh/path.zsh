
export GOOGLE_APPLICATION_CREDENTIALS="/usr/local/devConfig/firebase/helseoversiktdev.json"
export BREW_HOME="/usr/local/opt/"
export CASK_HOME="/usr/local/share/"
export JAVA_HOMES="/Library/Java/JavaVirtualMachines/"
export JAVA_HOME="`jenv javahome`"

export ANT_HOME="/usr/local/opt/ant"
# export ANT_HOME=/usr/local/opt/ant/libexec
export MAVEN_HOME="/usr/local/opt/maven"
export GRADLE_HOME="/usr/local/opt/gradle"
# export ANDROID_NDK_HOME="/usr/local/share/android-ndk"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
# /Users/predbjorn/Library/Android/sdk

# GEMS
export GEM_HOME="$HOME/.gem"
export PATH="$GEM_HOME/bin:$PATH"
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"
# export PATH="$GEM_HOME/ruby/2.6.0/bin:$PATH"
# Jenv
export PATH="$HOME/.jenv/bin:$PATH"
eval "$(jenv init -)"
#Java & Android
export PATH="$ANT_HOME/bin:$PATH"
export PATH="$MAVEN_HOME/bin:$PATH"
export PATH="$GRADLE_HOME/bin:$PATH"
export PATH="$ANDROID_HOME/tools:$PATH"
export PATH="$ANDROID_HOME/tools/bin:$PATH"
export PATH="$ANDROID_HOME/emulator:$PATH"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
export PATH="$ANDROID_HOME/build-tools/28.0.3:$PATH"
# If you want the latest version of the build-tools and not the most recently installed try this
# export PATH=$ANDROID_HOME/build-tools/$(ls $ANDROID_HOME/build-tools | sort | tail -1):$PATH



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
#   echo 'export PATH="/usr/local/opt/openssl/bin:$PATH"' >> ~/.zshrc

# For compilers to find openssl you may need to set:
#   export LDFLAGS="-L/usr/local/opt/openssl/lib"
#   export CPPFLAGS="-I/usr/local/opt/openssl/include"



export NVM_DIR="~/.nvm"
source $(brew --prefix nvm)/nvm.sh