#!/bin/sh

set -eu

proof_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
module_cache=${TMPDIR:-/tmp}/visor-v11-root-selector-module-cache

export CLANG_MODULE_CACHE_PATH=$module_cache
export SWIFTPM_MODULECACHE_OVERRIDE=$module_cache

swift build \
  --package-path "$proof_directory" \
  --target RootTestingSelectorProbe

set +e
probe_output=$(swift build \
  --package-path "$proof_directory" \
  --target RootTestingSelectorProbe \
  -Xswiftc -DVISOR_PROBE_INTERNAL_SELECTOR \
  -Xswiftc -DVISOR_PROBE_FILEPRIVATE_SELECTOR \
  -Xswiftc -DVISOR_PROBE_PRIVATE_SELECTOR \
  -Xswiftc -DVISOR_PROBE_COMPUTED_SELECTOR \
  -Xswiftc -DVISOR_PROBE_NESTED_SELECTOR \
  -Xswiftc -DVISOR_PROBE_PROJECTING_OVERLOAD 2>&1)
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "Expected selector contract probes to be rejected, but the target compiled." >&2
  exit 1
fi

verify_diagnostic() {
  description=$1
  expected_diagnostic=$2

  case "$probe_output" in
    *"$expected_diagnostic"*) ;;
    *)
      echo "The $description probe failed for an unexpected reason:" >&2
      echo "$probe_output" >&2
      exit 1
      ;;
  esac
}

verify_diagnostic \
  "an imported internal selector" \
  "'internalRevision' is inaccessible due to 'internal' protection level"
verify_diagnostic \
  "an imported fileprivate selector" \
  "'fileRevision' is inaccessible due to 'fileprivate' protection level"
verify_diagnostic \
  "a private-field selector" \
  "has no member 'hidden'"
verify_diagnostic \
  "a computed-property selector" \
  "has no member 'doubledCount'"
verify_diagnostic \
  "a nested-field selector" \
  "has no member 'count'"
verify_diagnostic \
  "a projecting history overload" \
  "extra argument 'hasExactChanges' in call"

echo "Root selectors remain flat and respect generated field visibility."
