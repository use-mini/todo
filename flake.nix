{
  description = "A todo reminder";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.todo = pkgs.stdenv.mkDerivation {
          pname = "todo";
          version = "0.1.0";
          src = ./.;
          nativeBuildInputs = [ pkgs.zig ];
          buildPhase = ''
            zig build install --prefix $out -Doptimize=ReleaseSafe
          '';
          dontInstall = true;
        };

        packages.default = self.packages.${system}.todo;

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.nixfmt
            pkgs.zig
            pkgs.zls
          ];
        };
      }
    );
}
