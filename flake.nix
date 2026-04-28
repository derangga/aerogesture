{
  description = "macOS daemon that translates trackpad swipe gestures into AeroSpace workspace commands";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "aarch64-darwin" "x86_64-darwin" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # SPM dependencies fetched directly -- no network needed during build.
        # To update: change rev + hash when bumping Package.resolved.
        tomlkit = pkgs.fetchFromGitHub {
          owner = "LebJe";
          repo = "TOMLKit";
          rev = "ec6198d37d495efc6acd4dffbd262cdca7ff9b3f";
          hash = "sha256-1aSH9Ze9rkk0EEDNoBlc/B6iXRmMx98ySOqhpfvQY2I=";
        };
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "aerogesture";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = [ pkgs.swift pkgs.swiftpm pkgs.git ];

          buildInputs = [ pkgs.apple-sdk_14 ];

          configurePhase = ''
            PROJECT_DIR=$(pwd)

            # Create a local git repo from the pre-fetched TOMLKit source.
            # SPM requires a bare git repo in .build/repositories/ -- it will not
            # use a plain directory. We manufacture one and update Package.resolved
            # with the resulting commit hash so the revision matches.
            TOMLKIT_WORK=$TMPDIR/tomlkit-work
            mkdir -p $TOMLKIT_WORK
            cp -r ${tomlkit}/. $TOMLKIT_WORK
            chmod -R u+w $TOMLKIT_WORK

            cd $TOMLKIT_WORK
            git init
            git config user.email "nix@build"
            git config user.name "Nix Build"
            git add -A
            GIT_AUTHOR_DATE="1970-01-01T00:00:00+0000" \
            GIT_COMMITTER_DATE="1970-01-01T00:00:00+0000" \
              git commit -m "Source"
            # Tag the version so SPM can resolve the semver requirement
            git tag 0.6.0
            TOMLKIT_REV=$(git rev-parse HEAD)

            cd $PROJECT_DIR

            # Populate SPM's repositories dir (bare clone) and checkouts dir.
            # The directory name TOMLKit-4b412b01 is derived by SPM from the
            # package URL https://github.com/LebJe/TOMLKit.git.
            # SPM validates that the remote URL matches, so we set the origin.
            mkdir -p .build/repositories
            git clone --bare $TOMLKIT_WORK .build/repositories/TOMLKit-4b412b01
            git -C .build/repositories/TOMLKit-4b412b01 remote set-url origin https://github.com/LebJe/TOMLKit.git

            mkdir -p .build/checkouts
            git clone $TOMLKIT_WORK .build/checkouts/TOMLKit

            chmod -R u+w .build

            # Update Package.resolved so the pinned revision matches our repo.
            sed -i "s/ec6198d37d495efc6acd4dffbd262cdca7ff9b3f/$TOMLKIT_REV/" Package.resolved
          '';

          buildPhase = ''
            export HOME=$TMPDIR
            swift build -c release --disable-sandbox --skip-update
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp -f .build/release/aerogesture $out/bin/
            mkdir -p $out/etc/aerogesture
            cp -f config.toml.example $out/etc/aerogesture/config.toml.example
          '';

          meta = with pkgs.lib; {
            description = "macOS daemon for trackpad swipe gestures to switch AeroSpace workspaces";
            homepage = "https://github.com/derangga/aerogesture";
            license = licenses.mit;
            platforms = [ "aarch64-darwin" "x86_64-darwin" ];
            mainProgram = "aerogesture";
          };
        };
      }
    );
}
