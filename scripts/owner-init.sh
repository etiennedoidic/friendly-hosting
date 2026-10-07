#!/bin/sh
# Usage: sudo ./scripts/owner-init.sh
# Env: TS_API_TOKEN FH_HOSTNAME FH_RENTER FH_SSH_KEY
#      FH_FOR_USER FH_PRIVATE_DIR FH_PUBLIC_DIR
#      FH_YES=1 FH_NONINTERACTIVE=1 FH_SKIP_RENTER=1 FH_SKIP_ACL=1 FH_TOKEN_DONE=1

set -eu
set -o pipefail 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$FH_ROOT/scripts/lib/common.sh"
. "$FH_ROOT/scripts/lib/macos-users.sh"
. "$FH_ROOT/scripts/lib/tailscale-api.sh"

fh_need_macos
fh_need_root

OWNER="$(fh_real_user)"
[ -n "$OWNER" ] && [ "$OWNER" != "root" ] || fh_die "run sudo ./owner-init.sh from the owner account (not sudo -u)"
if [ -z "${FH_FOR_USER:-}" ]; then
	FH_FOR_USER="$OWNER"
	export FH_FOR_USER
fi

echo "friendly-hosting owner-init"
echo "  owner unix user: $OWNER"
echo "  private dir:     $(fh_private_dir_for "$OWNER")"
echo "  public dir:      $(fh_public_dir_for "$OWNER")"
echo

if [ -z "${TS_API_TOKEN:-}" ] && [ -z "${FH_TOKEN_DONE:-}" ]; then
	echo "Paste a Tailscale API access token (Keys page, 90-day max)."
	echo "Empty is allowed: you will log in at a printed URL, and this script"
	echo "will skip ACL write + share-link creation."
	fh_prompt TS_API_TOKEN "API token" ""
	export TS_API_TOKEN
fi

if [ -z "${FH_HOSTNAME:-}" ]; then
	fh_prompt FH_HOSTNAME "Hostname for this machine" "$FH_DEFAULT_HOSTNAME"
fi
fh_valid_hostname "$FH_HOSTNAME" || fh_die "hostname must be DNS-safe (got: $FH_HOSTNAME)"
export FH_HOSTNAME

if [ -z "${FH_PUBLISH_MODE:-}" ]; then
	FH_PUBLISH_MODE="both"
fi
case "$FH_PUBLISH_MODE" in
private|public|both) ;;
*) fh_die "FH_PUBLISH_MODE must be private, public, or both" ;;
esac
export FH_PUBLISH_MODE

RENTER="${FH_RENTER:-}"
if [ -z "${FH_SKIP_RENTER:-}" ] && [ -z "$RENTER" ] && [ -z "${FH_NONINTERACTIVE:-}" ]; then
	echo "First renter short name is optional. Return skips; add people later with invite-renter.sh"
	fh_prompt RENTER "First renter short name" ""
fi
if [ -n "$RENTER" ]; then
	fh_valid_shortname "$RENTER" || fh_die "renter name must match ^[a-z][a-z0-9]{0,30}$"
fi

SSH_KEY="${FH_SSH_KEY:-}"
if [ -n "$RENTER" ] && [ -z "$SSH_KEY" ] && [ -z "${FH_NONINTERACTIVE:-}" ]; then
	fh_prompt SSH_KEY "Path to that renter's SSH public key (optional)" ""
fi
if [ -n "$SSH_KEY" ] && [ ! -f "$SSH_KEY" ]; then
	fh_die "SSH public key not found: $SSH_KEY"
fi

TS_BIN="$(fh_tailscale_bin)" || fh_die "install Homebrew Tailscale first: brew install --formula tailscale && sudo brew services start tailscale"
echo "using $TS_BIN"
"$TS_BIN" version | head -n 2 || true
echo

# --- ACL + auth key (token path) -----------------------------------------
AUTH_KEY=""
if [ -n "$TS_API_TOKEN" ]; then
	TS_TAILNET="${TS_TAILNET:--}"
	export TS_TAILNET
	echo "checking API token..."
	ts_api GET "/tailnet/{tailnet}/devices" >/dev/null || fh_die "token was rejected. Generate another at https://login.tailscale.com/admin/settings/keys"
	if [ "${FH_SKIP_ACL:-}" != "1" ]; then
		echo "This writes config/acl-policy.hujson to the tailnet (tag:host, shared users limited to tcp 443 and 22)."
		if fh_yes "Replace the tailnet ACL with the friendly-hosting policy?"; then
			ts_put_acl "$FH_ROOT/config/acl-policy.hujson"
			echo "ACL updated"
		else
			echo "skipped ACL write"
		fi
	fi
	echo "enabling MagicDNS..."
	if ts_enable_magicdns; then
		echo "MagicDNS on"
	else
		echo "MagicDNS API call failed; turn it on at https://login.tailscale.com/admin/dns"
	fi
	if ts_enable_https_certs; then
		echo "HTTPS certificates: API accepted"
	else
		echo
		echo "HUMAN — Toggle HTTPS certificates:"
		echo "  https://login.tailscale.com/admin/dns"
		echo "  Flip HTTPS on if it is not already. MagicDNS should already be on."
		echo
	fi
	echo "creating a tagged auth key ($FH_TAG)..."
	AUTH_KEY="$(ts_create_auth_key)" || AUTH_KEY=""
	[ -n "$AUTH_KEY" ] || echo "auth key create failed; falling back to browser login"
else
	echo "no API token: browser login, no ACL write, no share link"
fi

# --- tailscale up --------------------------------------------------------
_state="$(fh_backend_state || echo unknown)"
echo "tailscale backend: $_state"
if [ "$_state" != "Running" ]; then
	if [ -n "$AUTH_KEY" ]; then
		echo "tailscale up --auth-key (tagged) --hostname $FH_HOSTNAME"
		"$TS_BIN" up --auth-key="$AUTH_KEY" --hostname="$FH_HOSTNAME" --accept-routes=false --ssh=false --operator="$OWNER" || \
			"$TS_BIN" up --auth-key="$AUTH_KEY" --hostname="$FH_HOSTNAME" --accept-routes=false --ssh=false
	else
		echo "tailscale up --hostname $FH_HOSTNAME  (watch for a login URL)"
		"$TS_BIN" up --hostname="$FH_HOSTNAME" --accept-routes=false --ssh=false --operator="$OWNER" || \
			"$TS_BIN" up --hostname="$FH_HOSTNAME" --accept-routes=false --ssh=false
	fi
else
	echo "already running; setting hostname $FH_HOSTNAME"
	"$TS_BIN" set --hostname="$FH_HOSTNAME" 2>/dev/null || true
fi

echo
echo "tailscale status:"
"$TS_BIN" status || true

# --- homes ---------------------------------------------------------------
echo
echo "initializing $OWNER home layout (private + public dirs)"
fh_init_home "$OWNER"

if [ -n "$RENTER" ]; then
	echo "adding renter $RENTER"
	fh_add_renter "$RENTER"
	if [ -n "$SSH_KEY" ]; then
		fh_install_ssh_key "$RENTER" "$SSH_KEY"
	fi
fi

# --- Serve (private) -----------------------------------------------------
_serve_user() {
	_u="$1"
	_dir="$(fh_private_dir_for "$_u")"
	[ -d "$_dir" ] || fh_die "private dir missing for $_u: $_dir"
	echo "Serve https://<this-node>.ts.net/$_u/  ->  $_dir"
	"$TS_BIN" serve --bg --https=443 --set-path "/$_u" "$_dir"
}

_serve_user "$OWNER"
if [ -n "$RENTER" ]; then
	_serve_user "$RENTER"
fi
echo
echo "tailscale serve status:"
"$TS_BIN" serve status || true

# --- share invite --------------------------------------------------------
DNS="$(fh_dns_name || true)"
if [ -z "$DNS" ]; then
	DNS="${FH_HOSTNAME}.<tailnet>.ts.net"
fi

if [ -n "$RENTER" ] && [ -n "$TS_API_TOKEN" ]; then
	_devid="$(ts_device_id_by_hostname "$FH_HOSTNAME" || true)"
	if [ -z "$_devid" ]; then
		_devid="$(fh_tailscale_user status --json 2>/dev/null | fh_json_field Self.ID || true)"
	fi
	_invite=""
	if [ -n "$_devid" ]; then
		_invite="$(ts_create_device_invite "$_devid" || true)"
	fi
	echo
	if [ -n "$_invite" ]; then
		echo "Send the renter this share link (not the website URL):"
		echo "  $_invite"
	else
		echo "Could not mint a device-share link. In the admin console: Machines → $FH_HOSTNAME → Share."
	fi
	echo "Private URL (Tailscale must be on):"
	echo "  https://${DNS}/${RENTER}/"
	if [ -n "$SSH_KEY" ]; then
		echo "SSH (after they accept the share):"
		echo "  ssh -i ~/.ssh/mini ${RENTER}@${DNS}"
	else
		echo "No SSH key this run. When they send a .pub: sudo ./scripts/invite-renter.sh --ssh-key their.pub $RENTER"
	fi
elif [ -n "$RENTER" ]; then
	echo
	echo "No token, so no share link. Machines → $FH_HOSTNAME → Share, then send:"
	echo "  https://${DNS}/${RENTER}/"
fi

fh_write_ready "$OWNER"
echo
echo "owner-init: done."
echo "  private files: $(fh_private_dir_for "$OWNER")  (Serve port 443, tailnet only)"
echo "  public files:  $(fh_public_dir_for "$OWNER")  (not published yet)"
echo "  Public internet: docs/domain.md — sudo ./scripts/enable-public-www.sh $OWNER"
echo "  More people:     sudo ./scripts/invite-renter.sh <name>"
