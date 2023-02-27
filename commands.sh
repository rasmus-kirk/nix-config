# Install nix 
sudo sh <(curl -L https://nixos.org/nix/install) --daemon

# Make home manager available for install
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update

# Fix nix path stuff (this is dumb but necessary...)
export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels

# Install Home manager
nix-shell '<home-manager>' -A install

# Install programs
home-manager switch

# Add zsh to shells
# Set shell to zsh

# Add home manager bins to root user (Doesn't work for sudo), needs fix
echo 'export PATH=$PATH:/home/user/.nix-profile/bin:/nix/var/nix/profiles/default/bin' | sudo tee -a /root/.bashrc

