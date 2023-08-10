{
  description = "A very basic flake";

  inputs = {
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, crane, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        src = with pkgs; lib.cleanSourceWith {
          src = ./.; # The original, unfiltered source
          filter = path: type:
            (lib.hasSuffix "\.js" path) || # For plugin javascript
            (lib.hasSuffix "\.json" path) || # For package.json
            (lib.hasSuffix "\.ts" path) || # For typescript files
            (lib.hasSuffix "README.md" path) ||
            # Default filter from crane (allow .rs files)
            (craneLib.filterCargoSources path type)
          ;
        };

        crate = craneLib.buildPackage ({
          inherit src;
          doCheck = false;

          buildPhaseCargoCommand = ''
            mkdir -p $out/pkg

            wasm-pack build -t nodejs --out-dir $out/pkg $src
          '';

          buildInputs = with pkgs; [
            binaryen
            wasm-bindgen-cli
            wasm-pack
            nodejs
          ] ++ lib.optional stdenv.isLinux [
            strace
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.libiconv
          ];
        });
      in
      rec {
        checks = {
          inherit crate;
        };

        packages = {
          inherit crate;
        };

        devShells = {
          default = pkgs.mkShell {
            inputsFrom = builtins.attrValues self.checks.${system};

            buildInputs = with pkgs; [
              rust-analyzer
              nixfmt
              rnix-lsp
              nodePackages.typescript-language-server
            ];
          };
        };
      }
    );
}
