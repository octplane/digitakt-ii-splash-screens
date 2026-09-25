{
  description = "Digitakt II splash screen patch";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = pkgs.mkShell {
          # The scripts need python3 only; gcc is for building
          # elektron-firmware-tool, which handles compression and the
          # integrity trailer. See README.
          packages = [ pkgs.python3 pkgs.gcc pkgs.gnumake ];

          shellHook = ''
            echo "digitakt-ii-splash-screens: python $(python3 --version 2>&1 | cut -d' ' -f2)"
            [ -x ./elektron-firmware-tool/elektron-firmware-tool ] \
              || echo "  next: git clone https://github.com/mischa85/elektron-firmware-tool && (cd elektron-firmware-tool && make)"
          '';
        };
      });
}
