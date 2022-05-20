# Setup new computer:

1. install xcode
2. Log in to apple store
3. Follow these commands:

```
ssh-keygen -t ed25519 -C "prebenhafnor@gmail.com"

eval "$(ssh-agent -s)"

open ~/.ssh/config
touch ~/.ssh/config

Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519

ssh-add -K ~/.ssh/id_ed25519

pbcopy < ~/.ssh/id_ed25519.pub
```

add ssh to this: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account

4. Install this script

```
cd ~/dotfiles
chmod +x install.sh
./install.sh
```

5. install "code" command https://www.freecodecamp.org/news/how-to-open-visual-studio-code-from-your-terminal/

## Other apps

### vscode

Add git to sync

### iTerm2

```
p10k configure
```
