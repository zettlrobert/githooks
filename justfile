# githooks: shared git hooks and linters as a nix package. `just` lists the recipes.

set shell := ["bash", "-euo", "pipefail", "-c"]

[private]
default:
    @just --list --unsorted

# fixture tests for the hook scripts (fast, no build)
test:
    tests/run.sh

# build the package into ./result
build:
    nix build

# fixture tests and the end-to-end test inside the nix sandbox
check:
    nix flake check

# run this repo's own hooks on every tracked file (dogfooding)
lint:
    lefthook run pre-commit --all-files --no-stage-fixed
    shellcheck -s sh -o check-extra-masked-returns,check-set-e-suppressed,require-double-brackets,add-default-case,quote-safe-variables hooks/*.sh tests/*.sh bin/*
    shfmt -i 2 -d hooks/*.sh tests/*.sh bin/*
