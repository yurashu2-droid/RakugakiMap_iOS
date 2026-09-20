#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tool_root="$repo_root/.build/tools/XcodeGen"
tool_commit=21ac9944b0ab546a07422dbed86f33dd2ebd76f8

# CIでも手元でも同じバージョンでprojectを生成する。
if [[ ! -d "$tool_root/.git" ]]; then
  mkdir -p "$(dirname "$tool_root")"
  git clone --depth 1 --branch 2.44.1 https://github.com/yonaskolb/XcodeGen.git "$tool_root"
fi
if [[ "$(git -C "$tool_root" rev-parse HEAD)" != "$tool_commit" ]]; then
  echo 'XcodeGenのcommitが指定バージョンと一致しません。' >&2
  exit 1
fi
swift build --package-path "$tool_root" --configuration release --product xcodegen
tool_bin="$(swift build --package-path "$tool_root" --configuration release --show-bin-path)"
"$tool_bin/xcodegen" generate --spec "$repo_root/project.yml" --project "$repo_root"
