#!/bin/sh

set -eu

proof_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
module_cache=${TMPDIR:-/tmp}/visor-v11-root-selector-module-cache

export CLANG_MODULE_CACHE_PATH=$module_cache
export SWIFTPM_MODULECACHE_OVERRIDE=$module_cache

swift build \
  --package-path "$proof_directory" \
  --target RootTestingSelectorProbe

verify_rejected() {
  flag=$1
  description=$2
  expected_diagnostic=$3

  set +e
  output=$(swift build \
    --package-path "$proof_directory" \
    --target RootTestingSelectorProbe \
    -Xswiftc "-D$flag" 2>&1)
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "Expected $description to be rejected, but the target compiled." >&2
    exit 1
  fi

  case "$output" in
    *"$expected_diagnostic"*) ;;
    *)
      echo "The $description probe failed for an unexpected reason:" >&2
      echo "$output" >&2
      exit 1
      ;;
  esac
}

verify_rejected \
  VISOR_PROBE_INTERNAL_SELECTOR \
  "an imported internal selector" \
  "'internalRevision' is inaccessible due to 'internal' protection level"
verify_rejected \
  VISOR_PROBE_FILEPRIVATE_SELECTOR \
  "an imported fileprivate selector" \
  "'fileRevision' is inaccessible due to 'fileprivate' protection level"
verify_rejected \
  VISOR_PROBE_PRIVATE_SELECTOR \
  "a private-field selector" \
  "has no member 'hidden'"
verify_rejected \
  VISOR_PROBE_COMPUTED_SELECTOR \
  "a computed-property selector" \
  "has no member 'doubledCount'"
verify_rejected \
  VISOR_PROBE_NESTED_SELECTOR \
  "a nested-field selector" \
  "has no member 'count'"
verify_rejected \
  VISOR_PROBE_PROJECTING_OVERLOAD \
  "a projecting history overload" \
  "extra argument 'hasExactChanges' in call"

echo "Root selectors remain flat and respect generated field visibility."
