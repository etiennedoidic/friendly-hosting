# shellcheck shell=sh
# Callers set TS_API_TOKEN. TS_TAILNET defaults to "-" (the token's tailnet).

ts_api() {
	_method="$1"
	_path="$2"
	shift 2
	[ -n "${TS_API_TOKEN:-}" ] || fh_die "TS_API_TOKEN is empty"
	_tailnet="${TS_TAILNET:--}"
	_encoded="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe="-"))' "$_tailnet")"
	_url="$FH_API_BASE$(printf '%s' "$_path" | sed "s|{tailnet}|$_encoded|g")"
	_tmp="$(mktemp -t fh-ts-api.XXXXXX)"
	_code="$(
		curl -sS -u "${TS_API_TOKEN}:" \
			-X "$_method" \
			-H "Accept: application/json" \
			-H "Content-Type: application/json" \
			-o "$_tmp" \
			-w '%{http_code}' \
			"$_url" \
			"$@"
	)" || _code="000"
	_body="$(cat "$_tmp")"
	rm -f "$_tmp"
	case "$_code" in
	2*) printf '%s\n' "$_body" ;;
	*)
		echo "Tailscale API $_method $_url -> HTTP $_code" >&2
		printf '%s\n' "$_body" >&2
		return 1
		;;
	esac
}

ts_create_auth_key() {
	_body="$(python3 -c '
import json
print(json.dumps({
  "capabilities": {
    "devices": {
      "create": {
        "reusable": False,
        "ephemeral": False,
        "preauthorized": True,
        "tags": ["'"$FH_TAG"'"]
      }
    }
  },
  "expirySeconds": 3600,
  "description": "friendly-hosting owner-init"
}))
')"
	ts_api POST "/tailnet/{tailnet}/keys" --data "$_body" | fh_json_field key
}

ts_put_acl() {
	_acl="$1"
	[ -f "$_acl" ] || fh_die "ACL file missing: $_acl"
	# If-Match: * replaces the console policy; owner-init confirms first.
	ts_api POST "/tailnet/{tailnet}/acl" -H "If-Match: *" --data-binary "@$_acl" >/dev/null
}

ts_enable_magicdns() {
	ts_api POST "/tailnet/{tailnet}/dns/preferences" --data '{"magicDNS":true}' >/dev/null
}

ts_enable_https_certs() {
	# Field name has moved; 4xx means the caller should print the DNS console URL.
	if ts_api POST "/tailnet/{tailnet}/dns/preferences" --data '{"magicDNS":true,"httpsCertsEnabled":true}' >/dev/null 2>&1; then
		return 0
	fi
	if ts_api POST "/tailnet/{tailnet}/settings" --data '{"acmeEnabled":true}' >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

ts_device_id_by_hostname() {
	_want="$1"
	ts_api GET "/tailnet/{tailnet}/devices" | python3 -c '
import json, sys
want = sys.argv[1].lower()
data = json.load(sys.stdin)
devices = data.get("devices") or []
for d in devices:
    names = [d.get("hostname") or "", d.get("name") or ""]
    dns = (d.get("dnsName") or "").rstrip(".").split(".")[0]
    names.append(dns)
    if any(n.lower() == want for n in names if n):
        print(d.get("id") or "")
        break
' "$_want"
}

ts_create_device_invite() {
	_id="$1"
	[ -n "$_id" ] || return 1
	_resp="$(ts_api POST "/device/${_id}/device-invites" --data '{"multiUse":true,"allowExitNode":false}')" || return 1
	printf '%s\n' "$_resp" | python3 -c '
import json, sys
d = json.load(sys.stdin)
inv = d.get("invites")[0] if isinstance(d.get("invites"), list) and d["invites"] else d
for key in ("inviteUrl", "url", "InviteURL"):
    if inv.get(key):
        print(inv[key])
        break
'
}
