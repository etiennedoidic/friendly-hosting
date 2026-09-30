#!/bin/sh
# Usage: sudo ./scripts/invite-renter.sh [--ssh-key FILE] [--no-invite] [--invite] <shortname>
# Env: TS_API_TOKEN (optional; without it, print console Share instructions)

set -eu
set -o pipefail 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$FH_ROOT/scripts/lib/common.sh"
. "$FH_ROOT/scripts/lib/macos-users.sh"
. "$FH_ROOT/scripts/lib/tailscale-api.sh"

fh_need_macos
fh_need_root

SSH_KEY=""
FORCE_INVITE=""
SKIP_INVITE=""
NAME=""

while [ $# -gt 0 ]; do
	case "$1" in
	--ssh-key)
		[ $# -ge 2 ] || fh_die "--ssh-key needs a path"
		SSH_KEY="$2"
		shift 2
		;;
	--no-invite)
		SKIP_INVITE=1
		shift
		;;
	--invite)
		FORCE_INVITE=1
		shift
		;;
	-h|--help)
		echo "usage: sudo $0 [--ssh-key FILE] [--no-invite] [--invite] <shortname>"
		exit 0
		;;
	-*)
		fh_die "unknown flag: $1"
		;;
	*)
		NAME="$1"
		shift
		break
		;;
	esac
done

[ -n "$NAME" ] || fh_die "usage: sudo $0 [--ssh-key FILE] <shortname>"
fh_valid_shortname "$NAME" || fh_die "short name must match ^[a-z][a-z0-9]{0,30}$"

EXISTED=0
if fh_user_exists "$NAME"; then
	EXISTED=1
	echo "user $NAME already exists"
	fh_init_home "$NAME"
else
	fh_add_renter "$NAME"
fi

if [ -n "$SSH_KEY" ]; then
	fh_install_ssh_key "$NAME" "$SSH_KEY"
fi

TS_BIN="$(fh_tailscale_bin)" || fh_die "tailscale CLI not found"
_dir="$(fh_private_dir_for "$NAME")"
echo "Serve https://<this-node>.ts.net/${NAME}/  ->  $_dir"
"$TS_BIN" serve --bg --https=443 --set-path "/$NAME" "$_dir" || \
	fh_die "tailscale serve failed. Has owner-init joined this node?"

DNS="$(fh_dns_name || true)"
[ -n "$DNS" ] || DNS="<hostname>.<tailnet>.ts.net"

WANT_INVITE=1
if [ -n "$SKIP_INVITE" ]; then
	WANT_INVITE=0
elif [ "$EXISTED" -eq 1 ] && [ -n "$SSH_KEY" ] && [ -z "$FORCE_INVITE" ]; then
	WANT_INVITE=0
	echo "existing user + --ssh-key: not minting a new share link (pass --invite to force)"
fi

INVITE=""
if [ "$WANT_INVITE" -eq 1 ]; then
	if [ -z "${TS_API_TOKEN:-}" ]; then
		echo "Paste an API token to mint a share link, or empty to use the admin console."
		fh_prompt TS_API_TOKEN "API token" ""
		export TS_API_TOKEN
	fi
	if [ -n "${TS_API_TOKEN:-}" ]; then
		TS_TAILNET="${TS_TAILNET:--}"
		export TS_TAILNET
		_host="${FH_HOSTNAME:-}"
		if [ -z "$_host" ]; then
			_host="$(fh_tailscale_user status --json 2>/dev/null | fh_json_field Self.HostName || true)"
		fi
		_devid="$(ts_device_id_by_hostname "${_host:-mini}" || true)"
		if [ -z "$_devid" ]; then
			_devid="$(fh_tailscale_user status --json 2>/dev/null | fh_json_field Self.ID || true)"
		fi
		if [ -n "$_devid" ]; then
			INVITE="$(ts_create_device_invite "$_devid" || true)"
		fi
	fi
fi

echo
echo "renter: $NAME"
echo "private URL: https://${DNS}/${NAME}/"
if [ -n "$INVITE" ]; then
	echo "share link: $INVITE"
elif [ "$WANT_INVITE" -eq 1 ]; then
	echo "share link: create one in the admin console (Machines → this Mini → Share)"
fi
if [ -n "$SSH_KEY" ]; then
	echo "ssh: ssh -i ~/.ssh/mini ${NAME}@${DNS}"
else
	echo "no SSH key this run; they can send a .pub later and you rerun with --ssh-key"
fi
echo "public files will live in $(fh_public_dir_for "$NAME") — see docs/domain.md"
echo "invite-renter: done."
