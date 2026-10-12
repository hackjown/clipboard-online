#!/bin/bash
# 校验自定义 URL scheme `clipboard`（Bark 推送深链 clipboard://item/<uuid>）仍在最终产物的 Info.plist 里。
# 用法：verify_scheme.sh <x.ipa | Foo.app>
set -euo pipefail
src="$1"; work=""
if [[ "$src" == *.ipa ]]; then work="$(mktemp -d)"; unzip -q "$src" -d "$work"; app="$(ls -d "$work"/Payload/*.app | head -1)"; else app="$src"; fi
plist="$app/Info.plist"; [ -f "$plist" ] || plist="$app/Contents/Info.plist"
echo "=== $plist"
if /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" "$plist" | tee /dev/stderr | grep -qx "[[:space:]]*clipboard"; then
  echo "OK: URL scheme clipboard:// 已注册"
else
  echo "ERROR: Info.plist 里没有 clipboard scheme"; [ -n "$work" ] && rm -rf "$work"; exit 1
fi
[ -n "$work" ] && rm -rf "$work"
