#################
##   INSTALL   ##
#################

MACHINE="$1"

pushd "$HOME" || echo "Error: unable to go to $HOME"

# Install nix (https://github.com/DeterminateSystems/nix-installer)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Clone repo
nix run nixpkgs#git -- clone https://github.com/rasmus-kirk/nix-config.git

# Rename cloned repo
mv nix-config .system-configuration

# Enter cloned repo
cd .system-configuration

# Install configuration using flakes
nix run home-manager/master -- switch -b backup --flake .#"$MACHINE"

##################
## POST INSTALL ##
##################

# Add home manager bins to root user
# You can also just use `sudo -E command` instead
sudo sed '/Defaults.*secure_path/ s|"$|:/home/user/.nix-profile/bin"|' /etc/sudoers > /tmp/sudoers && sudo visudo -c -f /tmp/sudoers && cat /tmp/sudoers | sudo tee /etc/sudoers
