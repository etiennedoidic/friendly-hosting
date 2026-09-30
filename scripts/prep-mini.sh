#!/bin/sh
# Keep a headless Mini reachable. Skip on a laptop (this turns sleep off).
# Usage: sudo ./scripts/prep-mini.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FH_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$FH_ROOT/scripts/lib/common.sh"

fh_need_macos
fh_need_root

echo "prep-mini: keep this Mac awake, turn SSH on, warn about FileVault."
echo

echo "1. sleep off, disks awake, restart after power loss, wake-on-LAN if supported"
echo "   pmset -a sleep 0 disksleep 0 autorestart 1 womp 1"
pmset -a sleep 0 disksleep 0 autorestart 1 womp 1
echo

echo "2. Remote Login (OpenSSH) on. Screen Sharing / Remote Management left alone."
if command -v systemsetup >/dev/null 2>&1; then
	systemsetup -setremotelogin on
else
	echo "   systemsetup missing; enable Remote Login in System Settings → Sharing."
fi
echo

echo "3. FileVault (not changed by this script)"
_fv="$(fdesetup status 2>/dev/null || echo "unknown")"
echo "   $_fv"
case "$_fv" in
*"FileVault is On"*)
	echo
	echo "   WARNING: after a power loss this Mac sits at the disk-unlock screen."
	echo "   Nothing (Tailscale, SSH, Funnel) comes back until someone types the"
	echo "   password at a keyboard. For a truly headless host, turn FileVault off"
	echo "   yourself, or keep a keyboard on site. This script will not toggle it."
	echo
	;;
esac

echo "4. LaunchDaemons directory exists (cloudflared jobs install here later)"
mkdir -p /Library/LaunchDaemons

echo "5. Time Machine: exclude ~/.friendly-hosting on homes that have it"
for _st in /Users/*/.friendly-hosting; do
	if [ -d "$_st" ]; then
		tmutil addexclusion "$_st" >/dev/null 2>&1 || true
		echo "   excluded $_st"
	fi
done
echo

echo "6. headless-ready summary"
echo "   pmset:"
pmset -g | grep -E '^[ ]*(sleep|disksleep|autorestart|womp) ' || pmset -g
echo "   FileVault: $_fv"
echo "   Remote Login: $(systemsetup -getremotelogin 2>/dev/null || echo unknown)"
if _ts="$(fh_tailscale_bin 2>/dev/null)"; then
	echo "   tailscale: $_ts"
	"$_ts" version 2>/dev/null | head -n 1 || true
	if command -v brew >/dev/null 2>&1; then
		brew services list 2>/dev/null | grep -i tailscale || true
	fi
else
	echo "   tailscale: not installed yet (owner.md step 3)"
fi
echo
echo "prep-mini: done. Next is owner-init.sh."
