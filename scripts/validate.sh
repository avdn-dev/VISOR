#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

run_stage() {
  description=$1
  shift

  printf '\n==> %s\n' "$description"
  "$@"
}

run_stage "Root debug tests" swift test
run_stage "Root release tests" swift test -c release

for proof_package in \
  Tests/Fixtures/V11RootGatewayExternalProof \
  Tests/Fixtures/V11RootTestingExternalProof \
  Tests/Fixtures/V11RootTestDoublesExternalProof
do
  run_stage "$proof_package debug tests" \
    swift test --package-path "$proof_package"
  run_stage "$proof_package release tests" \
    swift test -c release --package-path "$proof_package"
done

run_stage "Gateway access-control contracts" \
  sh Tests/Fixtures/V11RootGatewayExternalProof/verify-access-control.sh
run_stage "Testing selector contracts" \
  sh Tests/Fixtures/V11RootTestingExternalProof/verify-selector-contracts.sh

documentation_workspace=$(mktemp -d /tmp/visor-docc-validation.XXXXXX)
trap 'rm -rf -- "$documentation_workspace"' EXIT
documentation_output="$documentation_workspace/archive"
module_cache="$documentation_workspace/module-cache"
mkdir -p "$documentation_output" "$module_cache"

printf '\n==> %s\n' "VISOR DocC archive"
CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
swift package --allow-writing-to-directory "$documentation_output" \
  generate-documentation --target VISOR \
  --output-path "$documentation_output" \
  --transform-for-static-hosting \
  --hosting-base-path VISOR

run_stage "Unstaged whitespace checks" git diff --check
run_stage "Staged whitespace checks" git diff --cached --check

printf '\nVISOR validation passed.\n'
