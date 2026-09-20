#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$repo_root" <<'PY'
import os
from pathlib import Path
from urllib.parse import urlparse
import sys

url = os.environ.get("SUPABASE_URL", "")
key = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")
if not url or not key:
    print("検証用Supabase設定なしでビルドします。")
    raise SystemExit(0)

parsed = urlparse(url)
if parsed.scheme != "https" or not parsed.hostname or parsed.path not in ("", "/"):
    raise SystemExit("Supabase URLの形式が不正です。")
if not key.startswith("sb_publishable_") or any(c.isspace() for c in key):
    raise SystemExit("公開可能なSupabaseキーが設定されていません。")

config = Path(sys.argv[1]) / "MapGrapherIOS/Configuration/Local.xcconfig"
escaped_url = url.replace("://", ":/$()/", 1)
config.write_text(
    f"SUPABASE_URL = {escaped_url}\nSUPABASE_PUBLISHABLE_KEY = {key}\n",
    encoding="utf-8",
)
print("検証用Supabase設定をビルドへ適用しました。")
PY
