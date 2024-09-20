{
  lib,
  pkgs,
  nixosOptionsDoc,
  inputs,
  ...
}: let
  # Make sure the used package is scrubbed to avoid actually
  # instantiating derivations.
  # evaluate our options
  evalHome = lib.evalModules {
    # TODO: understand why pkgs needs to be passed here
    specialArgs = {inherit pkgs;};
    modules = [
      {
        # disabled checking that all option definitions have matching declarations
        config._module.check = false;
      }
      inputs.home-manager.nixosModules.default
      ./home-manager
    ];
  };
  # generate our docs
  optionsDocHome = nixosOptionsDoc {
    inherit (evalHome) options;
  };

  # Same for nixos
  evalNixos = lib.evalModules {
    specialArgs = {inherit pkgs;};
    modules = [
      {
        config._module.check = false;
      }
      inputs.home-manager.nixosModules.default
      ./nixos
      #./nixos/servarr
      #./nixos/nixosScripts
    ];
  };
  optionsDocNixos = nixosOptionsDoc {
    inherit (evalNixos) options;
  };
in pkgs.stdenv.mkDerivation {
    name = "nixdocs2html";
    src = ./.;
    buildInputs = with pkgs; [ pandoc ];
    phases = ["unpackPhase" "buildPhase"];
    buildPhase = ''
      tmpdir=$(mktemp -d)
      #tmpdir=$out/debug
      mkdir -p $out
      mkdir -p $tmpdir
      cp -r docs $out

      buildpandoc () {
        filepath="$1"
        title="$2"
        filename=$(basename -- "$filepath")
        filename_no_ext="''${filename%.*}"

        pandoc \
          --standalone \
          --metadata title="$title" \
          --metadata date="$(date -u '+%Y-%m-%d - %H:%M:%S %Z')" \
          --highlight-style docs/pandoc/gruvbox.theme \
          --template docs/pandoc/template.html \
          --css docs/pandoc/style.css \
          --lua-filter docs/pandoc/lua/indent-code-blocks.lua \
          --lua-filter docs/pandoc/lua/anchor-links.lua \
          --lua-filter docs/pandoc/lua/code-default-to-nix.lua \
          --lua-filter docs/pandoc/lua/headers-lvl2-to-lvl3.lua \
          --lua-filter docs/pandoc/lua/remove-declared-by.lua \
          --lua-filter docs/pandoc/lua/inline-to-fenced-nix.lua \
          --lua-filter docs/pandoc/lua/remove-module-args.lua \
          -V lang=en \
          -V --mathjax \
          -f markdown+smart \
          -o $out/"$filename_no_ext".html \
          "$filepath"
      }

      # Generate nixos md docs
      cat ${optionsDocNixos.optionsCommonMark} > "$tmpdir"/nixos.md
      # Generate home-manager md docs
      cat ${optionsDocHome.optionsCommonMark} > "$tmpdir"/home.md

      buildpandoc "$tmpdir"/nixos.md "Nixos Modules - Options Documentation"
      buildpandoc "$tmpdir"/home.md "Home Manager Modules - Options Documentation"

      pandoc \
        --standalone \
        --highlight-style docs/pandoc/gruvbox.theme \
        --metadata title="Kirk Modules - Option Documentation" \
        --metadata date="$(date -u '+%Y-%m-%d - %H:%M:%S %Z')" \
        --css /docs/pandoc/style.css \
        --template docs/pandoc/template.html \
        -V lang=en \
        -V --mathjax \
        -f markdown+smart \
        -o $out/index.html \
        docs/index.md
    '';
  }



