#!/bin/sh

set -eu

proof_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
module_cache=${TMPDIR:-/tmp}/visor-v11-root-gateway-module-cache

export CLANG_MODULE_CACHE_PATH=$module_cache
export SWIFTPM_MODULECACHE_OVERRIDE=$module_cache

swift build \
  --package-path "$proof_directory" \
  --target RootGatewayAccessControlProbe

verify_inaccessible() {
  target=$1
  flag=$2
  member=$3
  access_level=${4:-package}

  set +e
  output=$(swift build \
    --package-path "$proof_directory" \
    --target "$target" \
    -Xswiftc "-D$flag" 2>&1)
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "Expected $member access to fail, but the target compiled." >&2
    exit 1
  fi

  case "$output" in
    *"'$member' is inaccessible due to '$access_level' protection level"*|\
    *"'$member' initializer is inaccessible due to '$access_level' protection level"*) ;;
    *)
      echo "The $member probe failed for an unexpected reason:" >&2
      echo "$output" >&2
      exit 1
      ;;
  esac
}

verify_inaccessible \
  RootGatewayAccessControlProbe \
  VISOR_PROBE_LAZY_VIEW_MODEL \
  viewModel \
  internal
verify_inaccessible RootGatewayAccessControlProbe VISOR_PROBE_FIELD_NAME name
verify_inaccessible RootGatewayAccessControlProbe VISOR_PROBE_FIELD_IDENTITY identity
verify_inaccessible RootGatewayAccessControlProbe VISOR_PROBE_FIELD_ELIGIBILITY isDirectReference
verify_inaccessible RootGatewayAccessControlProbe VISOR_PROBE_ERASED_NAME name
verify_inaccessible RootGatewayAccessControlProbe VISOR_PROBE_ERASED_IDENTITY identity
verify_inaccessible RootGatewayAccessControlProbe VISOR_PROBE_ERASED_READ read
verify_inaccessible RootGatewayAccessControlProbe VISOR_PROBE_ROUTER_LEVEL level
verify_inaccessible \
  RootGatewayAccessControlProbe \
  VISOR_PROBE_ROUTER_ROOT_DESTINATION \
  rootDestination
verify_inaccessible RootGatewayAccessControlProbe VISOR_PROBE_ROUTER_IS_ACTIVE isActive

verify_get_only() {
  flag=$1
  member=$2

  set +e
  output=$(swift build \
    --package-path "$proof_directory" \
    --target RootGatewayAccessControlProbe \
    -Xswiftc "-D$flag" 2>&1)
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "Expected $member assignment to fail, but the target compiled." >&2
    exit 1
  fi

  case "$output" in
    *"'$member' is a get-only property"*) ;;
    *)
      echo "The $member assignment probe failed for an unexpected reason:" >&2
      echo "$output" >&2
      exit 1
      ;;
  esac
}

verify_get_only VISOR_PROBE_SHEET_SETTER presentingSheet
verify_get_only VISOR_PROBE_FULL_SCREEN_SETTER presentingFullScreen

verify_hidden_type() {
  flag=$1
  type_name=$2

  set +e
  output=$(swift build \
    --package-path "$proof_directory" \
    --target RootObservationAccessControlProbe \
    -Xswiftc "-D$flag" 2>&1)
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "Expected $type_name access to fail, but the target compiled." >&2
    exit 1
  fi

  case "$output" in
    *"module 'VISOR' has no member named '$type_name'"*|*"cannot find '$type_name' in scope"*) ;;
    *)
      echo "The $type_name probe failed for an unexpected reason:" >&2
      echo "$output" >&2
      exit 1
      ;;
  esac
}

verify_inaccessible \
  RootObservationAccessControlProbe \
  VISOR_PROBE_VISITOR_INIT \
  _ObservationRecipeVisitor
verify_hidden_type VISOR_PROBE_SESSION _ObservationSession
verify_hidden_type VISOR_PROBE_LANE _ObservationLane
verify_hidden_type VISOR_PROBE_RECIPE _ObservationRecipe
verify_inaccessible RootObservationAccessControlProbe VISOR_PROBE_SOURCE_IDENTITY _visorIdentity
verify_inaccessible \
  RootObservationAccessControlProbe \
  VISOR_PROBE_RECIPE_FACTORY \
  _visorMakeObservationRecipes

echo "Root gateway metadata and observation lifecycle controls remain package-inaccessible."
