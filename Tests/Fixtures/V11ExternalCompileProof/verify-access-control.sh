#!/bin/sh

set -eu

proof_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
module_cache=${TMPDIR:-/tmp}/visor-v11-external-module-cache

export CLANG_MODULE_CACHE_PATH=$module_cache
export SWIFTPM_MODULECACHE_OVERRIDE=$module_cache

swift build \
  --package-path "$proof_directory" \
  --target ExternalAccessControlProbe

verify_inaccessible() {
  flag=$1
  member=$2

  set +e
  output=$(swift build \
    --package-path "$proof_directory" \
    --target ExternalAccessControlProbe \
    -Xswiftc "-D$flag" 2>&1)
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "Expected $member access to fail, but the target compiled." >&2
    exit 1
  fi

  case "$output" in
    *"'$member' is inaccessible due to 'package' protection level"*) ;;
    *)
      echo "The $member probe failed for an unexpected reason:" >&2
      echo "$output" >&2
      exit 1
      ;;
  esac
}

verify_unnameable() {
  flag=$1
  type=$2

  set +e
  output=$(swift build \
    --package-path "$proof_directory" \
    --target ExternalAccessControlProbe \
    -Xswiftc "-D$flag" 2>&1)
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "Expected $type to be unnameable, but the target compiled." >&2
    exit 1
  fi

  case "$output" in
    *"cannot find '$type' in scope"*) ;;
    *)
      echo "The $type probe failed for an unexpected reason:" >&2
      echo "$output" >&2
      exit 1
      ;;
  esac
}

verify_inaccessible VISOR_PROBE_FIELD_NAME name
verify_inaccessible VISOR_PROBE_FIELD_IDENTITY identity
verify_inaccessible VISOR_PROBE_FIELD_ELIGIBILITY isDirectReference
verify_unnameable VISOR_PROBE_OBSERVATION_SESSION _ObservationSession
verify_unnameable VISOR_PROBE_OBSERVATION_LANE _ObservationLane
verify_unnameable VISOR_PROBE_OBSERVATION_RECIPE _ObservationRecipe
verify_inaccessible VISOR_PROBE_SOURCE_OPEN _visorOpen
verify_inaccessible VISOR_PROBE_SOURCE_IDENTITY _visorIdentity
verify_unnameable VISOR_PROBE_OBSERVATION_RUNTIME _ObservationRuntime

set +e
visitor_output=$(swift build \
  --package-path "$proof_directory" \
  --target ExternalAccessControlProbe \
  -Xswiftc "-DVISOR_PROBE_RECIPE_VISITOR_INIT" 2>&1)
visitor_status=$?
set -e

if [ "$visitor_status" -eq 0 ]; then
  echo "Expected the recipe visitor initializer to remain inaccessible." >&2
  exit 1
fi

case "$visitor_output" in
  *"'_ObservationRecipeVisitor' initializer is inaccessible due to 'package' protection level"*) ;;
  *)
    echo "The recipe visitor initializer probe failed for an unexpected reason:" >&2
    echo "$visitor_output" >&2
    exit 1
    ;;
esac

echo "External descriptor metadata, recipe storage and lifecycle controls remain package-inaccessible."
