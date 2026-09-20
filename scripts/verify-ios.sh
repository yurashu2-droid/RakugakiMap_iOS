#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:-all}"
case "$mode" in
  core|unit|ui|build|all) ;;
  *) echo '指定可能: core / unit / ui / build / all' >&2; exit 2 ;;
esac
if [[ "$mode" == core || "$mode" == all ]]; then
  swift test --package-path "$repo_root/Packages/MapGrapherCore"
fi
if [[ "$mode" == core ]]; then exit 0; fi
if [[ "$mode" == unit || "$mode" == ui || "$mode" == all ]]; then
  : "${IOS_SIMULATOR_ID:?利用するSimulatorのUDIDを設定してください}"
  xcrun simctl list devices available --json | python3 -c '
import json, os, sys
devices = json.load(sys.stdin)["devices"]
valid = any(device["udid"] == os.environ["IOS_SIMULATOR_ID"]
            for runtime, values in devices.items() if "iOS" in runtime
            for device in values)
if not valid:
    sys.exit("IOS_SIMULATOR_IDが利用可能なiOS Simulatorに一致しません。")
'
fi
if [[ ! -d "$repo_root/MapGrapherIOS.xcodeproj" ]]; then
  bash "$repo_root/scripts/generate-project.sh"
fi
common=(-project "$repo_root/MapGrapherIOS.xcodeproj" CODE_SIGNING_ALLOWED=NO)
if [[ "$mode" == build || "$mode" == all ]]; then
  xcodebuild build "${common[@]}" -scheme MapGrapherIOS -destination 'generic/platform=iOS'
fi
if [[ "$mode" == unit || "$mode" == ui || "$mode" == all ]]; then
  : "${IOS_SIMULATOR_ID:?利用するSimulatorのUDIDを設定してください}"
  results="$repo_root/.build/verification/$(date -u +%Y%m%dT%H%M%SZ)-$$"
  mkdir -p "$results"
  if [[ "$mode" == unit || "$mode" == all ]]; then
    xcodebuild test "${common[@]}" -scheme MapGrapherIOS -parallel-testing-enabled NO -destination "platform=iOS Simulator,id=$IOS_SIMULATOR_ID" \
      -only-testing:MapGrapherIOSTests -resultBundlePath "$results/unit.xcresult"
  fi
  if [[ "$mode" == ui || "$mode" == all ]]; then
    xcodebuild test "${common[@]}" -scheme MapGrapherIOSUI -parallel-testing-enabled NO -destination "platform=iOS Simulator,id=$IOS_SIMULATOR_ID" \
      -only-testing:MapGrapherIOSUITests -resultBundlePath "$results/ui.xcresult"
  fi
fi
