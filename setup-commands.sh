# Install nix (https://github.com/DeterminateSystems/nix-installer)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Install configuration using flakes
nix run home-manager/master -- switch -b backup

##################
## POST INSTALL ##
##################

# Add home manager bins to root user
sudo sed '/Defaults.*secure_path/ s|"$|:/home/user/.nix-profile/bin"|' /etc/sudoers > /tmp/sudoers && sudo visudo -c -f /tmp/sudoers && cat /tmp/sudoers | sudo tee /etc/sudoers

##################
##     NOTES    ##
##################

# Fix nix path stuff (this is dumb but necessary...)
# NOTE: Not necessary with flakes it seems
#export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels

# TODO: Add zsh to shells
# NOTE: Should be fixed in current version, we add `exec zsh` to bashrc which should "just work"

# This one below might not be necessary...
# NOTE: Don't remember what this does lol
#echo 'export PATH=$PATH:/home/user/.nix-profile/bin:/nix/var/nix/profiles/default/bin' | sudo tee -a /root/.bashrc
