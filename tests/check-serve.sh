#!/bin/sh
# MIME / index.html checks. Default: local loopback, no Mini.
# Usage: ./tests/check-serve.sh [--local|--tailscale]

set -eu
set -o pipefail 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="local"
while [ $# -gt 0 ]; do
	case "$1" in
	--local) MODE="local"; shift ;;
	--tailscale) MODE="tailscale"; shift ;;
	-h|--help)
		echo "usage: $0 [--local|--tailscale]"
		exit 0
		;;
	*) echo "unknown arg: $1" >&2; exit 2 ;;
	esac
done

FIX="$FH_ROOT/fixtures/srv"
[ -f "$FIX/index.html" ] || { echo "missing $FIX/index.html" >&2; exit 1; }

PASS=0
FAIL=0
pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL + 1)); }

check_url() {
	_url="$1"
	_expect_sub="$2"
	_expect_ct="$3"
	_hdr="$(mktemp -t fh-hdr.XXXXXX)"
	_body="$(mktemp -t fh-body.XXXXXX)"
	curl -sS -D "$_hdr" -o "$_body" "$_url" || true
	_code="$(awk 'NR==1 {print $2}' "$_hdr")"
	_ct="$(awk '{k=$0; gsub("\r",""); if (tolower(k) ~ /^content-type:/) { print k; exit }}' "$_hdr")"
	if [ "$_code" = "200" ] && grep -q "$_expect_sub" "$_body"; then
		pass "$_url 200 and body contains '${_expect_sub}'"
	else
		fail "$_url expected 200 + '${_expect_sub}' (got HTTP ${_code:-none})"
	fi
	if [ -n "$_expect_ct" ]; then
		case "$(printf '%s' "$_ct" | tr '[:upper:]' '[:lower:]')" in
		*"$_expect_ct"*) pass "$_url Content-Type has $_expect_ct" ;;
		*) fail "$_url Content-Type wanted $_expect_ct (got ${_ct:-empty})" ;;
		esac
	fi
	rm -f "$_hdr" "$_body"
}

echo "tailscale binary: $(command -v tailscale 2>/dev/null || echo 'not installed')"
if command -v tailscale >/dev/null 2>&1; then
	tailscale version 2>/dev/null | head -n 2 || true
fi
echo

if [ "$MODE" = "local" ]; then
	PORT=18765
	python3 "$FH_ROOT/scripts/lib/serve-static.py" "$PORT" "$FIX" &
	PID=$!
	trap 'kill $PID 2>/dev/null || true' EXIT
	i=0
	while [ "$i" -lt 20 ]; do
		if curl -sf -o /dev/null "http://127.0.0.1:${PORT}/"; then
			break
		fi
		i=$((i + 1))
		sleep 0.1
	done
	BASE="http://127.0.0.1:${PORT}"
	check_url "$BASE/" "<h1>Placeholder" ""
	check_url "$BASE/manifest.webmanifest" "start_url" "application/manifest+json"
	check_url "$BASE/sw.js" "skipWaiting" "javascript"
else
	command -v tailscale >/dev/null 2>&1 || { echo "tailscale not installed" >&2; exit 1; }
	PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
	echo "attaching fixtures/srv on a throwaway Serve path /_fh-check"
	tailscale serve --bg --https=443 --set-path /_fh-check "$FIX"
	DNS="$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')"
	BASE="https://${DNS}/_fh-check"
	echo "fetching $BASE (needs this machine on the tailnet)"
	check_url "$BASE/" "<h1>Placeholder" ""
	check_url "$BASE/manifest.webmanifest" "start_url" "manifest"
	check_url "$BASE/sw.js" "skipWaiting" "javascript"
	echo "leave /_fh-check in place until you run: tailscale serve reset"
fi

echo
echo "summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
