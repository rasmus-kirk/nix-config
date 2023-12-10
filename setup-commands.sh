#################
##   INSTALL   ##
#################

MACHINE=$(echo "")

# Install nix (https://github.com/DeterminateSystems/nix-installer)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Install configuration using flakes
nix run home-manager/master -- switch -b backup --flake .#"$MACHINE"

##################
## POST INSTALL ##
##################

# Add home manager bins to root user
sudo sed '/Defaults.*secure_path/ s|"$|:/home/user/.nix-profile/bin"|' /etc/sudoers > /tmp/sudoers && sudo visudo -c -f /tmp/sudoers && cat /tmp/sudoers | sudo tee /etc/sudoers
