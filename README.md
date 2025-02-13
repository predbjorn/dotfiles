# Setup new computer:

1. install xcode
2. Log in to apple store
3. Give full system access System Settings > Privacy & Security > Full Disk Access
4. Create ssh key for git:

```
cd ~/dotfiles
chmod +x githssh.sh
./githssh.sh
```

5. Add the ssh key to git by following the instructions [here](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account).

6. Git login terminal:
   Select SSH, then ssh file and login in with browser.

```
gh auth login
```

7. Install this script (you`ll have to run it multiple times to get throuh)

```
chmod +x install.sh
./install.sh
```

<!-- ## THIS SHOULD WORK
5. install "code" command https://www.freecodecamp.org/news/how-to-open-visual-studio-code-from-your-terminal/ -->

## Other apps

### vscode

Add git to sync

### iTerm2

```
p10k configure
```
