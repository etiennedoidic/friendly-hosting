# Friendly-hosting

Shared hosting on a Mac you own: unix users, Tailscale Serve for private
files, Funnel or Cloudflare for a public `~/www` tree, SSH into a home
directory. Tailscale is the web server for the private site. There is no
nginx or Caddy.

This folder does not know about any particular app. Defaults are `~/srv`
(private, tailnet only) and `~/www` (public static files). Another product
can point those at different paths with `FH_PRIVATE_DIR` and `FH_PUBLIC_DIR`.

## Who does what

The **owner** sits at the Mini once, pastes one Tailscale API token, and
runs `owner-init.sh`. The **renter** installs Tailscale, taps a share
link, and opens a URL. If they want a shell, they send a public key and
SSH in as a non-admin user. They cannot sudo or write outside their home.

Private files live on port 443 over the tailnet. Public static files live
in `~/www` on Funnel 8443 or Cloudflare. Do not Funnel port 443.

## Files

- `docs/owner.md` — owner click list.
- `docs/renter.md` — renter click list (phone site, SSH, public www).
- `docs/domain.md` — public `www/` for owner and renter: Funnel (Tier 0) and real domain (Tier 1).
- `docs/appendix-family-invite.md` — invite the renter onto the owner’s tailnet instead of a device share.
- `docs/client-variant.md` — Homebrew Tailscale on the Mini; App Store is fine on phones and renter laptops.
- `scripts/prep-mini.sh` — keep the Mini awake and reachable after a reboot (skip on a laptop).
- `scripts/owner-init.sh` — first-time Tailscale join, ACL, Serve, optional first renter.
- `scripts/invite-renter.sh` — add a renter or an SSH key.
- `scripts/enable-public-www.sh` — Funnel one user’s `~/www` on 8443.
- `scripts/setup-cloudflared.sh` — Tier 1 real URL, run as that macOS user.
- `scripts/lib/tailscale-api.sh` — Tailscale admin API helpers.
- `scripts/lib/macos-users.sh` — create a non-admin user and `~/srv` + `~/www`.
- `scripts/lib/serve-static.py` — loopback static server (Cloudflare origins; Serve fallback if MIME fails).
- `config/acl-policy.hujson` — tailnet policy the owner script writes.
- `config/cloudflared.yml` — named tunnel template for one user’s www tree.
- `config/launchd/com.friendlyhosting.cloudflared.plist` — example LaunchDaemon (the setup script writes a per-user copy).
- `fixtures/srv/` — throwaway private site copied into `~/srv`.
- `fixtures/www/` — throwaway public tree copied into `~/www`.
- `tests/check-serve.sh` — MIME / index.html checks (local by default; `--tailscale` optional).
- `tests/acceptance.md` — stopwatch checks on a real Mini.

## Order

On a Mini: `prep-mini.sh` (if used) → `owner-init.sh` → `invite-renter.sh` as needed → `enable-public-www.sh` / `setup-cloudflared.sh` when you want the internet to see `www/`.

On a laptop used only to develop the scripts: skip `prep-mini.sh`.
