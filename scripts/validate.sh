#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

run_stage() {
  stage_description=$1
  shift

  printf '\n==> %s\n' "$stage_description"
  "$@"
}

usage() {
  printf '%s\n' \
    "usage: scripts/validate.sh [root <debug|release|all> | external <debug|release|all> <package-path> | api | documentation [output-path]]" \
    >&2
}

run_tests() {
  test_description=$1
  test_configuration=$2
  shift 2

  case "$test_configuration" in
    debug)
      run_stage "$test_description debug tests" swift test "$@"
      ;;
    release)
      run_stage "$test_description release tests" swift test -c release "$@"
      ;;
    all)
      run_tests "$test_description" debug "$@"
      run_tests "$test_description" release "$@"
      ;;
    *)
      printf 'unsupported test configuration: %s\n' "$test_configuration" >&2
      usage
      return 2
      ;;
  esac
}

run_style_check() {
  run_stage "Airbnb Swift style" \
    swift package --allow-writing-to-package-directory format \
      --lint \
      --paths \
      Package.swift \
      Sources \
      Tests/VISORMacroTests \
      Tests/VISORObservationTests \
      Tests/VISORTestDoublesTests \
      Tests/VISORTestingTests \
      Tests/VISORTests \
      Tests/Fixtures/V11RootGatewayExternalProof/Package.swift \
      Tests/Fixtures/V11RootGatewayExternalProof/Sources \
      Tests/Fixtures/V11RootGatewayExternalProof/Tests \
      Tests/Fixtures/V11RootTestingExternalProof/Package.swift \
      Tests/Fixtures/V11RootTestingExternalProof/Sources \
      Tests/Fixtures/V11RootTestingExternalProof/Tests \
      Tests/Fixtures/V11RootTestDoublesExternalProof/Package.swift \
      Tests/Fixtures/V11RootTestDoublesExternalProof/Sources \
      Tests/Fixtures/V11RootTestDoublesExternalProof/Tests
}

run_root_tests() {
  test_configuration=$1

  case "$test_configuration" in
    release|all) run_style_check ;;
  esac

  run_tests "Root" "$test_configuration"
}

run_api_contracts() {
  run_stage "Gateway access-control contracts" \
    sh Tests/Fixtures/V11RootGatewayExternalProof/verify-access-control.sh
  run_stage "Testing selector contracts" \
    sh Tests/Fixtures/V11RootTestingExternalProof/verify-selector-contracts.sh
}

documentation_workspace=

clean_documentation_workspace() {
  case "$documentation_workspace" in
    /tmp/visor-docc-validation.*)
      rm -rf -- "$documentation_workspace"
      ;;
    "") ;;
    *)
      printf 'refusing to remove unexpected documentation workspace: %s\n' \
        "$documentation_workspace" >&2
      return 1
      ;;
  esac
}

trap clean_documentation_workspace EXIT

run_documentation() {
  documentation_workspace=$(mktemp -d /tmp/visor-docc-validation.XXXXXX)
  module_cache="$documentation_workspace/module-cache"

  if [ "$#" -eq 0 ]; then
    documentation_output="$documentation_workspace/archive"
  else
    case "$1" in
      docs|"$repository_root/docs")
        documentation_output="$repository_root/docs"
        ;;
      *)
        printf 'unsupported documentation output path: %s\n' "$1" >&2
        return 2
        ;;
    esac
  fi

  mkdir -p "$documentation_output" "$module_cache"
  documentation_output=$(CDPATH= cd -- "$documentation_output" && pwd)

  case "$documentation_output" in
    "$repository_root/docs"|/tmp/visor-docc-validation.*/*|/private/tmp/visor-docc-validation.*/*) ;;
    *)
      printf 'unsupported documentation output path: %s\n' \
        "$documentation_output" >&2
      return 2
      ;;
  esac

  printf '\n==> %s\n' "Combined public-product DocC archive"
  CLANG_MODULE_CACHE_PATH="$module_cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
  swift package --allow-writing-to-directory "$documentation_output" \
    generate-documentation \
    --target VISORObservation \
    --target VISOR \
    --target VISORTesting \
    --target VISORTestDoubles \
    --enable-experimental-combined-documentation \
    --output-path "$documentation_output" \
    --experimental-skip-synthesized-symbols \
    --warnings-as-errors \
    --transform-for-static-hosting \
    --hosting-base-path VISOR
}

run_complete_validation() {
  run_root_tests all

  for proof_package in \
    Tests/Fixtures/V11RootGatewayExternalProof \
    Tests/Fixtures/V11RootTestingExternalProof \
    Tests/Fixtures/V11RootTestDoublesExternalProof
  do
    run_tests "$proof_package" all --package-path "$proof_package"
  done

  run_api_contracts
  run_documentation

  run_stage "Unstaged whitespace checks" git diff --check
  run_stage "Staged whitespace checks" git diff --cached --check

  printf '\nVISOR validation passed.\n'
}

if [ "$#" -eq 0 ]; then
  run_complete_validation
  exit 0
fi

mode=$1
shift

case "$mode" in
  root)
    if [ "$#" -ne 1 ]; then
      usage
      exit 2
    fi
    run_root_tests "$1"
    ;;
  external)
    if [ "$#" -ne 2 ]; then
      usage
      exit 2
    fi
    configuration=$1
    proof_package=$2
    run_tests "$proof_package" "$configuration" --package-path "$proof_package"
    ;;
  api)
    if [ "$#" -ne 0 ]; then
      usage
      exit 2
    fi
    run_api_contracts
    ;;
  documentation)
    if [ "$#" -gt 1 ]; then
      usage
      exit 2
    fi
    run_documentation "$@"
    ;;
  *)
    usage
    exit 2
    ;;
esac
