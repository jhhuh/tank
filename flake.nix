{
  description = "Tank - protocol-centric workspace system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        haskellPackages = pkgs.haskellPackages.override {
          overrides = hself: hsuper: {
            tank = hself.callCabal2nix "tank" ./. {};
            tank-layout = hself.callCabal2nix "tank-layout" ./tank-layout {};
          };
        };

        tank = haskellPackages.tank;

        mkdocsEnv = pkgs.python3.withPackages (ps: [
          ps.mkdocs-material
          ps.mkdocs
        ]);

        conceptEnv = pkgs.python3.withPackages (ps: [ ps.pillow ]);
        conceptFont = "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf";
      in
      {
        packages = {
          default = tank;
          docs = pkgs.runCommand "tank-docs" {
            nativeBuildInputs = [ mkdocsEnv ];
          } ''
            cp -r ${./docs-site}/* .
            mkdocs build -d $out
          '';
          concept-images = pkgs.runCommand "tank-concept-images" {
            nativeBuildInputs = [ conceptEnv ];
          } ''
            mkdir -p $out
            ${conceptEnv}/bin/python3 \
              ${./docs-site/docs/assets/concepts/render-concepts.py} all \
              --font ${conceptFont} --outdir $out
          '';
        };

        apps.default = {
          type = "app";
          program = "${tank}/bin/tank";
        };

        devShells.default = haskellPackages.shellFor {
          packages = p: [ p.tank p.tank-layout ];
          nativeBuildInputs = with pkgs; [
            # Haskell tooling
            cabal-install
            haskell-language-server
            haskellPackages.hspec-discover

            # Cap'n Proto
            capnproto

            # Documentation
            mkdocsEnv

            # Process management
            overmind
            tmux

            # General
            pkg-config
          ];
        };
      }
    );
}
