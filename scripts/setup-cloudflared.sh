#!/bin/sh
# Usage: ./scripts/setup-cloudflared.sh example.com
#        ./scripts/setup-cloudflared.sh example.com=hello other.com=photos
# Run as the unix user who owns ~/www (not root). Cloudflare tunnels proxy HTTP,
# so this starts a loopback static server per origin.

set -eu
set -o pipefail 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$FH_ROOT/scripts/lib/common.sh"

fh_need_macos

if [ "$(id -u)" -eq 0 ]; then
	fh_die "run this as the unix user who owns the public files, not as root"
fi

USER_NAME="$(id -un)"
PUB="$(fh_public_dir_for "$USER_NAME")"
ST="$(fh_state_dir_for "$USER_NAME")"
BIN="$ST/bin"
CFG="$ST/cloudflared.yml"
CRED_DIR="$ST/tunnels"
PY="$ST/serve-static.py"

[ -d "$PUB" ] || fh_die "public dir missing: $PUB"
mkdir -p "$BIN" "$CRED_DIR" "$ST/logs"

[ $# -ge 1 ] || fh_die "usage: $0 example.com  OR  $0 example.com=hello other.com=photos"

MAPS="$ST/host-map.txt"
: >"$MAPS"
for _arg in "$@"; do
	_host="${_arg%%=*}"
	_folder=""
	case "$_arg" in
	*=*) _folder="${_arg#*=}" ;;
	esac
	[ -n "$_host" ] || fh_die "empty hostname in $_arg"
	_root="$PUB"
	if [ -n "$_folder" ]; then
		_root="$PUB/$_folder"
		[ -d "$_root" ] || fh_die "folder missing: $_root (create it, add index.html)"
	fi
	printf '%s\t%s\n' "$_host" "$_root" >>"$MAPS"
done

if [ -z "${CF_API_TOKEN:-}" ]; then
	echo "Create an API token on Cloudflare that can manage tunnels and DNS"
	echo "(Account Cloudflare Tunnel Edit, Zone DNS Edit, Zone Read)."
	fh_prompt CF_API_TOKEN "Cloudflare API token" ""
fi
[ -n "$CF_API_TOKEN" ] || fh_die "Cloudflare API token required"

cf_api() {
	_method="$1"
	_path="$2"
	shift 2
	_tmp="$(mktemp -t fh-cf.XXXXXX)"
	_code="$(
		curl -sS -X "$_method" \
			-H "Authorization: Bearer ${CF_API_TOKEN}" \
			-H "Content-Type: application/json" \
			-o "$_tmp" \
			-w '%{http_code}' \
			"https://api.cloudflare.com/client/v4${_path}" \
			"$@"
	)" || _code="000"
	_body="$(cat "$_tmp")"
	rm -f "$_tmp"
	echo "$_body" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("success") else 1)' 2>/dev/null \
		|| {
			echo "Cloudflare API $_method $_path -> HTTP $_code" >&2
			printf '%s\n' "$_body" >&2
			return 1
		}
	printf '%s\n' "$_body"
}

echo "looking up Cloudflare account..."
_acc_json="$(cf_api GET "/accounts")"
ACCOUNT_ID="$(printf '%s\n' "$_acc_json" | python3 -c 'import json,sys; r=json.load(sys.stdin)["result"]; print(r[0]["id"] if r else "")')"
[ -n "$ACCOUNT_ID" ] || fh_die "no Cloudflare account visible with this token"
echo "account: $ACCOUNT_ID"

# Install into the user's home: renters cannot brew.
_arch="$(uname -m)"
case "$_arch" in
arm64) _url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64" ;;
x86_64) _url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64" ;;
*) fh_die "unsupported arch $_arch" ;;
esac
if [ ! -x "$BIN/cloudflared" ]; then
	echo "installing cloudflared into $BIN"
	curl -fsSL -o "$BIN/cloudflared" "$_url"
	chmod 755 "$BIN/cloudflared"
fi
cp "$FH_ROOT/scripts/lib/serve-static.py" "$PY"
chmod 755 "$PY"

TUNNEL_ID=""
if [ -f "$ST/tunnel-id" ]; then
	TUNNEL_ID="$(tr -d '[:space:]' <"$ST/tunnel-id")"
	echo "reusing tunnel $TUNNEL_ID"
fi
if [ -z "$TUNNEL_ID" ]; then
	_tname="fh-${USER_NAME}"
	echo "creating named tunnel $_tname"
	_tjson="$(cf_api POST "/accounts/${ACCOUNT_ID}/cfd_tunnel" --data "$(python3 -c 'import json,sys; print(json.dumps({"name":sys.argv[1],"config_src":"local"}))' "$_tname")")"
	TUNNEL_ID="$(printf '%s\n' "$_tjson" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["id"])')"
	printf '%s\n' "$_tjson" | python3 -c '
import json, sys, os
d = json.load(sys.stdin)["result"]
cred = d.get("credentials_file") or {}
if not cred:
    cred = {
        "AccountTag": d.get("account_tag") or d.get("accountTag") or "",
        "TunnelID": d.get("id") or "",
        "TunnelName": d.get("name") or "",
        "TunnelSecret": d.get("tunnel_secret") or d.get("tun_sec") or d.get("secret") or "",
    }
path = sys.argv[1]
with open(path, "w") as f:
    json.dump(cred, f)
os.chmod(path, 0o600)
' "$CRED_DIR/${TUNNEL_ID}.json"
	printf '%s\n' "$TUNNEL_ID" >"$ST/tunnel-id"
fi
CRED="$CRED_DIR/${TUNNEL_ID}.json"
[ -f "$CRED" ] || fh_die "missing tunnel credentials $CRED (delete $ST/tunnel-id and rerun)"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("TunnelSecret") and d.get("TunnelID") else 1)' "$CRED" \
	|| fh_die "incomplete Cloudflare tunnel credentials in $CRED (need TunnelID + TunnelSecret). Delete $ST/tunnel-id and rerun with a token that can create tunnels."

python3 - "$CFG" "$CRED" "$TUNNEL_ID" "$MAPS" "$ST" <<'PY'
import json, pathlib, sys
cfg_path, cred, tunnel_id, maps, st = sys.argv[1:6]
st = pathlib.Path(st)
port_file = st / "www-ports.json"
ports = json.loads(port_file.read_text()) if port_file.exists() else {}
next_port = max(ports.values(), default=18079) + 1
ingress = []
for line in pathlib.Path(maps).read_text().splitlines():
    if not line.strip():
        continue
    host, root = line.split("\t", 1)
    if root not in ports:
        ports[root] = next_port
        next_port += 1
    ingress.append({"hostname": host, "service": f"http://127.0.0.1:{ports[root]}"})
ingress.append({"service": "http_status:404"})
lines = [f"tunnel: {tunnel_id}", f"credentials-file: {cred}", "ingress:"]
for rule in ingress:
    if "hostname" in rule:
        lines += [f"  - hostname: {rule['hostname']}", f"    service: {rule['service']}"]
    else:
        lines.append(f"  - service: {rule['service']}")
pathlib.Path(cfg_path).write_text("\n".join(lines) + "\n")
port_file.write_text(json.dumps(ports, indent=2) + "\n")
PY

echo "wrote $CFG"

echo "creating/updating DNS CNAME records..."
while IFS="$(printf '\t')" read -r _host _root; do
	[ -n "$_host" ] || continue
	# Registered zone assumed to be the last two labels; create the CNAME by hand if this misses.
	_zone="$(python3 -c 'import sys; p=sys.argv[1].split("."); print(".".join(p[-2:]) if len(p)>=2 else p[0])' "$_host")"
	_zjson="$(cf_api GET "/zones?name=${_zone}")" || true
	_zid="$(printf '%s\n' "$_zjson" | python3 -c 'import json,sys; r=json.load(sys.stdin).get("result") or []; print(r[0]["id"] if r else "")')"
	if [ -z "$_zid" ]; then
		echo "  could not find zone for $_host (looked up $_zone). Create a CNAME $_host -> ${TUNNEL_ID}.cfargotunnel.com (proxied) by hand."
		continue
	fi
	_target="${TUNNEL_ID}.cfargotunnel.com"
	_existing="$(cf_api GET "/zones/${_zid}/dns_records?name=${_host}&type=CNAME")" || _existing=""
	_rid="$(printf '%s\n' "$_existing" | python3 -c 'import json,sys; r=(json.load(sys.stdin).get("result") or []); print(r[0]["id"] if r else "")')"
	_payload="$(python3 -c 'import json,sys; print(json.dumps({"type":"CNAME","name":sys.argv[1],"content":sys.argv[2],"proxied":True,"ttl":1}))' "$_host" "$_target")"
	if [ -n "$_rid" ]; then
		cf_api PUT "/zones/${_zid}/dns_records/${_rid}" --data "$_payload" >/dev/null
		echo "  updated CNAME $_host"
	else
		cf_api POST "/zones/${_zid}/dns_records" --data "$_payload" >/dev/null
		echo "  created CNAME $_host"
	fi
done <"$MAPS"

echo
echo "Installing LaunchDaemons (sudo). They run as $USER_NAME so they start at boot without a GUI login."

install_plist() {
	_label="$1"
	_plist_body="$2"
	_tmp="$(mktemp -t fh-plist.XXXXXX)"
	printf '%s\n' "$_plist_body" >"$_tmp"
	sudo cp "$_tmp" "/Library/LaunchDaemons/${_label}.plist"
	sudo chown root:wheel "/Library/LaunchDaemons/${_label}.plist"
	sudo chmod 644 "/Library/LaunchDaemons/${_label}.plist"
	rm -f "$_tmp"
	sudo launchctl bootout system "/Library/LaunchDaemons/${_label}.plist" 2>/dev/null || true
	sudo launchctl bootstrap system "/Library/LaunchDaemons/${_label}.plist"
}

python3 - "$ST/www-ports.json" "$USER_NAME" <<'PY' >/tmp/fh-static-jobs-$$.txt
import json, pathlib, sys
ports = json.loads(pathlib.Path(sys.argv[1]).read_text())
user = sys.argv[2]
for root, port in sorted(ports.items(), key=lambda kv: kv[1]):
    print(f"com.friendlyhosting.static.{user}.{port}\t{port}\t{root}")
PY

while IFS="$(printf '\t')" read -r _label _port _root; do
	[ -n "$_label" ] || continue
	_body="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
	<key>Label</key>
	<string>${_label}</string>
	<key>UserName</key>
	<string>${USER_NAME}</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/python3</string>
		<string>${PY}</string>
		<string>${_port}</string>
		<string>${_root}</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>${ST}/logs/static-${_port}.log</string>
	<key>StandardErrorPath</key>
	<string>${ST}/logs/static-${_port}.err</string>
</dict>
</plist>"
	install_plist "$_label" "$_body"
	echo "  static server $_root on 127.0.0.1:$_port"
done </tmp/fh-static-jobs-$$.txt
rm -f /tmp/fh-static-jobs-$$.txt

_cf_label="com.friendlyhosting.cloudflared.${USER_NAME}"
_cf_body="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
	<key>Label</key>
	<string>${_cf_label}</string>
	<key>UserName</key>
	<string>${USER_NAME}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${BIN}/cloudflared</string>
		<string>tunnel</string>
		<string>--config</string>
		<string>${CFG}</string>
		<string>run</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>${ST}/logs/cloudflared.log</string>
	<key>StandardErrorPath</key>
	<string>${ST}/logs/cloudflared.err</string>
</dict>
</plist>"
install_plist "$_cf_label" "$_cf_body"

echo
echo "Cloudflare terminates TLS and can see this public HTML as plaintext."
echo "Private files in $(fh_private_dir_for "$USER_NAME") are not in the tunnel."
echo "Edits: overwrite files under $PUB and refresh (purge Cloudflare cache if it sticks)."
echo "Add another hostname later by running this script again with extra hostname=folder pairs."
echo
while IFS="$(printf '\t')" read -r _host _root; do
	[ -n "$_host" ] || continue
	echo "  https://${_host}/   <-  $_root"
done <"$MAPS"
echo "setup-cloudflared: done."
