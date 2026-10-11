#!/bin/bash
# 校验 ATS：iOS10+/macOS10.12+ 只要出现 NSAllowsArbitraryLoadsForMedia / InWebContent / NSAllowsLocalNetworking，
# 系统会忽略 NSAllowsArbitraryLoads，导致明文 http 被拦（-1022）。所以必须「只有」NSAllowsArbitraryLoads=true。
# 用法：verify_ats.sh <x.ipa | Foo.app>   —— 逐个检查主 App 与 PlugIns/*.appex 的 Info.plist（macOS 用 PlistBuddy）
set -euo pipefail
PB=/usr/libexec/PlistBuddy
src="$1"
work=""
if [[ "$src" == *.ipa ]]; then
  work="$(mktemp -d)"; unzip -q "$src" -d "$work"; app="$(ls -d "$work"/Payload/*.app | head -1)"
else
  app="$src"
fi
fail=0
check() {
  local plist="$1"
  echo "=== $plist"
  $PB -c "Print :NSAppTransportSecurity" "$plist" || { echo "ERROR: 没有 NSAppTransportSecurity"; fail=1; return; }
  local v; v="$($PB -c "Print :NSAppTransportSecurity:NSAllowsArbitraryLoads" "$plist" 2>/dev/null || echo missing)"
  [ "$v" = "true" ] || { echo "ERROR: NSAllowsArbitraryLoads=$v（应为 true）"; fail=1; }
  for k in NSAllowsArbitraryLoadsForMedia NSAllowsArbitraryLoadsInWebContent NSAllowsLocalNetworking; do
    if $PB -c "Print :NSAppTransportSecurity:$k" "$plist" >/dev/null 2>&1; then
      echo "ERROR: 存在 $k，会让系统忽略 NSAllowsArbitraryLoads"; fail=1
    fi
  done
}
if [ -f "$app/Info.plist" ]; then check "$app/Info.plist"; else check "$app/Contents/Info.plist"; fi
for x in "$app"/PlugIns/*.appex; do [ -d "$x" ] && check "$x/Info.plist"; done
[ -n "$work" ] && rm -rf "$work"
[ $fail -eq 0 ] && echo "OK: ATS 配置正确" || { echo "ATS 校验失败"; exit 1; }
