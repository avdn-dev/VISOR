#!/bin/sh

set -eu

proof_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
module_cache=${TMPDIR:-/tmp}/visor-v11-root-gateway-module-cache

export CLANG_MODULE_CACHE_PATH=$module_cache
export SWIFTPM_MODULECACHE_OVERRIDE=$module_cache

swift build \
  --package-path "$proof_directory" \
  --target RootGatewayAccessControlProbe

probe_output=

run_rejected_batch() {
  target=$1
  description=$2
  shift 2

  set +e
  probe_output=$(swift build \
    --package-path "$proof_directory" \
    --target "$target" \
    "$@" 2>&1)
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "Expected $description to fail, but the target compiled." >&2
    exit 1
  fi
}

report_missing_diagnostic() {
  description=$1

  echo "The $description probe failed for an unexpected reason:" >&2
  echo "$probe_output" >&2
  exit 1
}

verify_inaccessible() {
  member=$1
  access_level=${2:-package}

  case "$probe_output" in
    *"'$member' is inaccessible due to '$access_level' protection level"*|\
    *"'$member' initializer is inaccessible due to '$access_level' protection level"*) ;;
    *) report_missing_diagnostic "$member access" ;;
  esac
}

verify_get_only() {
  member=$1

  case "$probe_output" in
    *"'$member' is a get-only property"*) ;;
    *) report_missing_diagnostic "$member assignment" ;;
  esac
}

verify_hidden_type() {
  type_name=$1

  case "$probe_output" in
    *"module 'VISOR' has no member named '$type_name'"*|*"cannot find '$type_name' in scope"*) ;;
    *) report_missing_diagnostic "$type_name access" ;;
  esac
}

run_rejected_batch \
  RootGatewayAccessControlProbe \
  "gateway access-control probes" \
  -Xswiftc -DVISOR_PROBE_LAZY_VIEW_MODEL \
  -Xswiftc -DVISOR_PROBE_FIELD_NAME \
  -Xswiftc -DVISOR_PROBE_FIELD_IDENTITY \
  -Xswiftc -DVISOR_PROBE_FIELD_ELIGIBILITY \
  -Xswiftc -DVISOR_PROBE_ERASED_READ \
  -Xswiftc -DVISOR_PROBE_SHEET_SETTER \
  -Xswiftc -DVISOR_PROBE_FULL_SCREEN_SETTER \
  -Xswiftc -DVISOR_PROBE_ROUTER_LEVEL \
  -Xswiftc -DVISOR_PROBE_ROUTER_ROOT_DESTINATION \
  -Xswiftc -DVISOR_PROBE_ROUTER_IS_ACTIVE

verify_inaccessible viewModel internal
verify_inaccessible name
verify_inaccessible identity
verify_inaccessible isDirectReference
verify_inaccessible read
verify_get_only presentingSheet
verify_get_only presentingFullScreen
verify_inaccessible level
verify_inaccessible rootDestination
verify_inaccessible isActive

run_rejected_batch \
  RootGatewayAccessControlProbe \
  "erased gateway metadata probes" \
  -Xswiftc -DVISOR_PROBE_ERASED_NAME \
  -Xswiftc -DVISOR_PROBE_ERASED_IDENTITY

verify_inaccessible name
verify_inaccessible identity

run_rejected_batch \
  RootObservationAccessControlProbe \
  "observation lifecycle access-control probes" \
  -Xswiftc -DVISOR_PROBE_VISITOR_INIT \
  -Xswiftc -DVISOR_PROBE_SESSION \
  -Xswiftc -DVISOR_PROBE_LANE \
  -Xswiftc -DVISOR_PROBE_RECIPE \
  -Xswiftc -DVISOR_PROBE_SOURCE_IDENTITY \
  -Xswiftc -DVISOR_PROBE_RECIPE_FACTORY

verify_inaccessible _ObservationRecipeVisitor
verify_hidden_type _ObservationSession
verify_hidden_type _ObservationLane
verify_hidden_type _ObservationRecipe
verify_inaccessible _visorIdentity
verify_inaccessible _visorMakeObservationRecipes

run_rejected_batch \
  RootGatewayAccessControlProbe \
  "binding payload type contract" \
  -Xswiftc -DVISOR_PROBE_BINDING_PAYLOAD

case "$probe_output" in
  *"cannot convert value of type 'Int' to expected argument type 'String'"*) ;;
  *) report_missing_diagnostic "binding payload type" ;;
esac

echo "Root gateway metadata and observation lifecycle controls remain package-inaccessible."
