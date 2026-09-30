# Client variant: which Tailscale to install where

The Mini that *hosts* files must run the Homebrew open-source `tailscaled`.
Phones and renter laptops can use the App Store / Play Store app.

## Mini (owner, hosting)

```
brew install --formula tailscale
sudo brew services start tailscale
```

Do not also install the Mac App Store Tailscale on this machine. The
store client is sandboxed: directory Serve and Funnel (point the node at
a folder) only work on the open-source daemon.

`owner-init.sh` will refuse to proceed if it cannot find a `tailscale`
CLI. `tests/check-serve.sh --tailscale` records `which tailscale` and
`tailscale version` so you can confirm you are not on the store binary.

## Phones (owner or renter)

App Store or Play Store. Sign in, accept the device-share link, open the
private HTTPS URL. Add to Home Screen uses Safari / Chrome; there is no
hosting app to install.

## Renter laptop (SSH / building)

App Store Tailscale is fine. The laptop is only a client on the share.
They do not Serve or Funnel directories. Homebrew on the laptop is
optional.

## If directory Serve fails MIME or index.html

Run `tests/check-serve.sh` (local, no Mini) and, on a Homebrew node,
`tests/check-serve.sh --tailscale`. If Tailscale serves `/` as a listing
or `.webmanifest` as `application/octet-stream`, the allowed exception
is `scripts/lib/serve-static.py` on loopback, with Serve pointing at
`http://127.0.0.1:<port>` instead of the folder. Cloudflare already uses
that process (tunnels cannot serve directories).
