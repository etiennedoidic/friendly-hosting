# shellcheck shell=sh
# Source after setting FH_ROOT.

: "${FH_ROOT:?set FH_ROOT before sourcing common.sh}"

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

FH_PRIVATE_NAME="${FH_PRIVATE_NAME:-srv}"
FH_PUBLIC_NAME="${FH_PUBLIC_NAME:-www}"
FH_TAG="${FH_TAG:-tag:host}"
FH_DEFAULT_HOSTNAME="${FH_DEFAULT_HOSTNAME:-mini}"
FH_API_BASE="${FH_API_BASE:-https://api.tailscale.com/api/v2}"

fh_die() {
	echo "error: $*" >&2
	exit 1
}

fh_need_macos() {
	[ "$(uname -s)" = "Darwin" ] || fh_die "this script only runs on macOS"
}

fh_need_root() {
	[ "$(id -u)" -eq 0 ] || fh_die "run with sudo"
}

fh_real_user() {
	if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
		printf '%s\n' "$SUDO_USER"
	else
		id -un
	fi
}

fh_home() {
	_u="$1"
	_h=""
	if command -v dscl >/dev/null 2>&1; then
		_h="$(dscl . -read "/Users/$_u" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
	fi
	if [ -z "$_h" ] && [ -d "/Users/$_u" ]; then
		_h="/Users/$_u"
	fi
	[ -n "$_h" ] || fh_die "no home directory for $_u"
	printf '%s\n' "$_h"
}

# FH_FOR_USER + FH_PRIVATE_DIR / FH_PUBLIC_DIR pin one user; everyone else gets ~/srv and ~/www.
fh_private_dir_for() {
	_u="$1"
	if [ -n "${FH_PRIVATE_DIR:-}" ] && [ "${FH_FOR_USER:-}" = "$_u" ]; then
		printf '%s\n' "$FH_PRIVATE_DIR"
		return
	fi
	printf '%s/%s\n' "$(fh_home "$_u")" "$FH_PRIVATE_NAME"
}

fh_public_dir_for() {
	_u="$1"
	if [ -n "${FH_PUBLIC_DIR:-}" ] && [ "${FH_FOR_USER:-}" = "$_u" ]; then
		printf '%s\n' "$FH_PUBLIC_DIR"
		return
	fi
	printf '%s/%s\n' "$(fh_home "$_u")" "$FH_PUBLIC_NAME"
}

fh_state_dir_for() {
	printf '%s/.friendly-hosting\n' "$(fh_home "$1")"
}

fh_valid_shortname() {
	echo "$1" | grep -Eq '^[a-z][a-z0-9]{0,30}$'
}

fh_valid_hostname() {
	echo "$1" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'
}

fh_user_exists() {
	dscl . -read "/Users/$1" UniqueID >/dev/null 2>&1
}

fh_prompt() {
	_var="$1"
	_msg="$2"
	_def="${3:-}"
	if [ -n "$_def" ]; then
		printf '%s [%s]: ' "$_msg" "$_def" >&2
	else
		printf '%s: ' "$_msg" >&2
	fi
	if [ -n "${FH_NONINTERACTIVE:-}" ] && [ -n "$_def" ]; then
		_ans="$_def"
		printf '%s\n' "$_ans" >&2
	else
		IFS= read -r _ans || _ans=""
	fi
	[ -n "$_ans" ] || _ans="$_def"
	eval "$_var=\$_ans"
}

fh_yes() {
	_msg="$1"
	if [ "${FH_YES:-}" = "1" ]; then
		return 0
	fi
	printf '%s [y/N]: ' "$_msg" >&2
	IFS= read -r _ans || _ans=""
	case "$_ans" in
	y|Y|yes|YES) return 0 ;;
	*) return 1 ;;
	esac
}

fh_json_field() {
	python3 -c '
import json, sys
path = sys.argv[1].split(".")
data = json.load(sys.stdin)
for key in path:
    if data is None:
        sys.exit(1)
    if isinstance(data, list):
        data = data[int(key)]
    else:
        data = data[key]
if isinstance(data, (dict, list)):
    json.dump(data, sys.stdout)
    sys.stdout.write("\n")
else:
    sys.stdout.write("" if data is None else str(data))
    sys.stdout.write("\n")
' "$1"
}

fh_tailscale_bin() {
	if command -v tailscale >/dev/null 2>&1; then
		command -v tailscale
		return
	fi
	for _p in /opt/homebrew/bin/tailscale /usr/local/bin/tailscale; do
		if [ -x "$_p" ]; then
			printf '%s\n' "$_p"
			return
		fi
	done
	return 1
}

fh_tailscale_user() {
	_bin="$(fh_tailscale_bin)" || fh_die "tailscale CLI not found"
	"$_bin" "$@"
}

fh_dns_name() {
	fh_tailscale_user status --json 2>/dev/null | fh_json_field Self.DNSName | sed 's/\.$//'
}

fh_backend_state() {
	fh_tailscale_user status --json 2>/dev/null | fh_json_field BackendState || echo "unknown"
}

fh_write_ready() {
	_u="$1"
	_dir="$(fh_state_dir_for "$_u")"
	mkdir -p "$_dir"
	{
		echo "hostname=${FH_HOSTNAME:-$FH_DEFAULT_HOSTNAME}"
		echo "mode=${FH_PUBLISH_MODE:-both}"
		echo "private=$(fh_private_dir_for "$_u")"
		echo "public=$(fh_public_dir_for "$_u")"
	} >"$_dir/ready"
	chmod 600 "$_dir/ready" 2>/dev/null || true
}
