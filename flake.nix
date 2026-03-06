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

        # Patch for capnp: GHC 9.10 tightened DuplicateRecordFields rules
        capnpDuplicateRecordFieldsPatch = pkgs.writeText "capnp-duplicate-record-fields.patch" ''
          --- a/lib/Capnp/GenHelpers/Rpc.hs
          +++ b/lib/Capnp/GenHelpers/Rpc.hs
          @@ -1,3 +1,4 @@
           {-# LANGUAGE DataKinds #-}
          +{-# LANGUAGE DuplicateRecordFields #-}
           {-# LANGUAGE FlexibleContexts #-}
           {-# LANGUAGE TypeFamilies #-}
        '';

        haskellPackages = pkgs.haskellPackages.override {
          overrides = hself: hsuper: {
            tank = hself.callCabal2nix "tank" ./. {};
            tank-layout = hself.callCabal2nix "tank-layout" ./tank-layout {};

            # capnp 0.18: relax bounds for GHC 9.10, add DuplicateRecordFields pragma
            capnp = pkgs.haskell.lib.dontCheck (pkgs.haskell.lib.appendPatch
              (pkgs.haskell.lib.doJailbreak hsuper.capnp)
              capnpDuplicateRecordFieldsPatch);

            # capnp transitive deps: broken or tight upper bounds on GHC 9.10
            supervisors = pkgs.haskell.lib.doJailbreak (pkgs.haskell.lib.unmarkBroken hsuper.supervisors);
            lifetimes = pkgs.haskell.lib.doJailbreak (pkgs.haskell.lib.unmarkBroken hsuper.lifetimes);
            network-simple = pkgs.haskell.lib.doJailbreak hsuper.network-simple;
            data-default-instances-vector = pkgs.haskell.lib.doJailbreak (pkgs.haskell.lib.unmarkBroken hsuper.data-default-instances-vector);
          };
        };

        tank = haskellPackages.tank;

        mkdocsEnv = pkgs.python3.withPackages (ps: [
          ps.mkdocs-material
          ps.mkdocs
        ]);

        fontConf = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };
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
            nativeBuildInputs = [ haskellPackages.tank-layout ];
            FONTCONFIG_FILE = fontConf;
          } ''
            mkdir -p $out
            tank-render-concepts all --outdir $out
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
