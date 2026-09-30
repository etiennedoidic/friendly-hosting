#!/bin/sh
# Funnel one user's ~/www on 8443. Serve and Funnel cannot share a port; 443 stays private.
# Usage: sudo ./scripts/enable-public-www.sh <shortname>

set -eu
set -o pipefail 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$FH_ROOT/scripts/lib/common.sh"

fh_need_macos
fh_need_root

NAME="${1:-}"
[ -n "$NAME" ] || fh_die "usage: sudo $0 <shortname>"
fh_valid_shortname "$NAME" || fh_die "short name must match ^[a-z][a-z0-9]{0,30}$"
fh_user_exists "$NAME" || fh_die "no such macOS user: $NAME"

PUB="$(fh_public_dir_for "$NAME")"
[ -d "$PUB" ] || fh_die "public dir missing: $PUB (create it, put an index.html in it)"

TS_BIN="$(fh_tailscale_bin)" || fh_die "tailscale CLI not found"

_try_funnel() {
	_port="$1"
	echo "Funnel https://<this-node>.ts.net:${_port}/${NAME}/  ->  $PUB"
	"$TS_BIN" funnel --bg --https="$_port" --set-path "/$NAME" "$PUB"
}

PORT=8443
if ! _out="$(_try_funnel 8443 2>&1)"; then
	echo "$_out"
	echo "8443 failed; trying 10000"
	PORT=10000
	_out="$(_try_funnel 10000 2>&1)" || {
		echo "$_out"
		echo
		echo "If the CLI printed a browser link, open it and approve Funnel"
		echo "(first time this tailnet uses Funnel). Then rerun this script."
		exit 1
	}
fi
printf '%s\n' "$_out"

DNS="$(fh_dns_name || true)"
[ -n "$DNS" ] || DNS="<hostname>.<tailnet>.ts.net"
echo
echo "Public base URL (Tailscale can be off on the phone):"
echo "  https://${DNS}:${PORT}/${NAME}/"
echo "A folder inside the public dir is a path, e.g. …/${NAME}/hello/"
echo
echo "Private Serve on 443 is unchanged. Do not Funnel 443."
echo "enable-public-www: done."
