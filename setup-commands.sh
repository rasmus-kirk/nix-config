# Install nix (https://github.com/DeterminateSystems/nix-installer)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Make home manager available for install
# TODO: Use flakes
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update

# Fix nix path stuff (this is dumb but necessary...)
export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels

# Install Home manager
nix-shell '<home-manager>' -A install

# Install programs
home-manager switch

##################
## POST INSTALL ##
##################

# Add zsh to shells
# Set shell to zsh

# Add home manager bins to root user
sudo sed '/Defaults.*secure_path/ s|"$|:/home/user/.nix-profile/bin"|' /etc/sudoers > /tmp/sudoers && sudo visudo -c -f /tmp/sudoers && cat /tmp/sudoers | sudo tee /etc/sudoers
# This one below might not be necessary...
echo 'export PATH=$PATH:/home/user/.nix-profile/bin:/nix/var/nix/profiles/default/bin' | sudo tee -a /root/.bashrc

##################
##     NOTES    ##
##################

# Remove super key action in popos:
#   gsettings set org.gnome.shell.extensions.pop-cosmic overlay-key-action 'WORKSPACES'
#   gsettings set org.gnome.mutter overlay-key ''
