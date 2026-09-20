#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$repo_root/scripts/generate-project.sh"
build_root="$repo_root/.build/ipa/$(date -u +%Y%m%dT%H%M%SZ)-$$"
output_root="$repo_root/.build/ipa-output"
mkdir -p "$build_root/Payload" "$output_root"

# iLoaderで利用者が署名するための実機用アプリ。Appleへのuploadは行わない。
xcodebuild archive -project "$repo_root/MapGrapherIOS.xcodeproj" \
  -scheme MapGrapherIOS -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$build_root/RakugakiMap.xcarchive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''
app="$build_root/RakugakiMap.xcarchive/Products/Applications/MapGrapherIOS.app"
test -f "$app/Info.plist"
test -f "$app/MapGrapherIOS"
ditto "$app" "$build_root/Payload/MapGrapherIOS.app"
ditto -c -k --keepParent "$build_root/Payload" "$output_root/RakugakiMap-unsigned.ipa"
unzip -tq "$output_root/RakugakiMap-unsigned.ipa"
(
  cd "$output_root"
  shasum -a256 RakugakiMap-unsigned.ipa > SHA256SUMS.txt
)
git -C "$repo_root" rev-parse HEAD > "$output_root/commit.txt"
echo "IPA: $output_root/RakugakiMap-unsigned.ipa"
