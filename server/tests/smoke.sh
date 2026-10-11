#!/usr/bin/env bash
# curl 冒烟：./tests/smoke.sh [base_url]
set -euo pipefail
B="${1:-http://127.0.0.1:8099}"; J='Content-Type: application/json'; ok(){ echo "  ✓ $1"; }
# register
curl -fsS -c /tmp/cj -X POST "$B/api/register" -H "$J" -d '{"username":"smoke_'$$'","password":"demo123"}' >/dev/null; ok register
curl -fsS -b /tmp/cj -X POST "$B/content" -H "$J" -d '{"content":"priv","visibility":"private"}' >/dev/null; ok add_private
curl -fsS -b /tmp/cj -X POST "$B/content" -H "$J" -d '{"content":"pub","visibility":"public"}' >/dev/null; ok add_public
echo x > /tmp/s.txt
curl -fsS -b /tmp/cj -F "file=@/tmp/s.txt" -F "visibility=public" "$B/upload_file" >/dev/null; ok upload
# guest
curl -fsS "$B/api/items?scope=public" | python3 -c 'import sys,json;d=json.load(sys.stdin);assert d["counts"]["public"]>=1'
ok guest_public
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$B/content" -H "$J" -d '{"content":"x"}')
[ "$code" = "401" ]; ok guest_cannot_write
curl -fsS -b /tmp/cj -X POST "$B/api/logout" >/dev/null; ok logout
echo "smoke OK"
