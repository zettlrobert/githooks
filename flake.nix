{
  description = "Shared git hooks and linters: lefthook, the tool set, their configs and the convention hooks as one package";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Every linter the base lefthook.yml and jobs/*.yml call. No git, no coreutils: hooks run from a git
      # process that has both, and bin/git would collide with nix-profiles core.
      tools =
        pkgs: with pkgs; [
          lefthook
          shellcheck
          shfmt
          ruff
          nixfmt
          statix
          deadnix
          yamllint
          markdownlint-cli2
          taplo
          hadolint
          actionlint
          biome
          gitleaks
        ];

      mkGithooks =
        pkgs:
        pkgs.symlinkJoin {
          name = "githooks";
          paths = tools pkgs;
          postBuild = ''
            share=$out/share/githooks
            mkdir -p $share/jobs
            cp ${./lefthook.yml} $share/lefthook.yml
            cp ${./jobs}/*.yml $share/jobs/
            cp ${./configs}/* $share/
            cp ${./hooks}/*.sh $share/
            chmod +x $share/*.sh
            # sourced by the installed git hook stubs before they look for lefthook (GUI git, plain terminals)
            printf 'PATH=%s/bin:$PATH\n' "$out" > $share/lefthookrc
            substitute ${./bin/githooks-install.in} $out/bin/githooks-install --subst-var out
            cp ${./bin/githooks-coverage} $out/bin/githooks-coverage
            chmod +x $out/bin/githooks-install $out/bin/githooks-coverage
          '';
        };
    in
    {
      packages = forAll (pkgs: {
        default = mkGithooks pkgs;
      });

      # `nix flake check`: the fixture tests for the hook scripts and the end-to-end test against the package.
      # Sandbox: git from nixpkgs, HOME in $TMPDIR, no network.
      checks = forAll (pkgs: {
        hooks =
          pkgs.runCommand "githooks-tests"
            {
              nativeBuildInputs = [
                pkgs.git
                (mkGithooks pkgs)
              ];
            }
            ''
              export HOME=$TMPDIR
              git config --global user.email t@t
              git config --global user.name t
              git config --global commit.gpgsign false
              git config --global init.defaultBranch main
              cp -r ${./.} src && chmod -R u+w src && cd src
              shellcheck -s sh hooks/*.sh tests/*.sh bin/*
              shfmt -i 2 -d hooks/*.sh tests/*.sh bin/*
              sh tests/run.sh
              if [ -f tests/integration.sh ]; then sh tests/integration.sh ${mkGithooks pkgs}; fi
              touch $out
            '';
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [
            (mkGithooks pkgs)
            pkgs.just
          ];
          shellHook = "githooks-install";
        };
      });

      formatter = forAll (pkgs: pkgs.nixfmt);
    };
}
