# Public static sites

The Mini serves whatever files are in `~/www/` right now. Save a file, refresh the browser.

The private site (`~/srv`) never goes public.

## Layout

```
~/srv/                 private site (tailnet only, port 443)
~/www/                 everything public
~/www/index.html
~/www/<sitename>/      any static site
~/.friendly-hosting/   credentials and tunnel config (not public)
```

## Shared: files → live page

Everyone does this the same way (owner on the Mini, renter over SSH).

1. Go to your home on the Mini (`pwd` is `/Users/<your-name>`).
2. Put the site in `~/www/` or `~/www/<sitename>/`. You need an `index.html` in that folder.
3. Look at the next section. If this user is **already published**, stop: open the URL and refresh. If this user has **never** been published, pick Tier 0 or Tier 1 below and do those steps **once**.

After the door is open, a new folder is the same as an edit: `mkdir ~/www/blog`, add `index.html`, refresh. No owner, no script.

### If you already published this user (edits and re-deploys)

You do **not** run `enable-public-www.sh` again. You do **not** need to ask the owner to re-deploy.

Funnel and Cloudflare read the folder from disk **on each request**. Overwrite `~/www/index.html`, then reload the page (shift-reload if the browser cached it).

- **Tier 0:** next request is the new file. Nothing to purge.
- **Tier 1:** same, unless Cloudflare cached the old page. Then hard-refresh, or Purge Cache in the Cloudflare dashboard.

You only need the owner again if the public URL stopped working (Mini reboot with Funnel/cloudflared down, or you want a *new person* published).

## Once: open the public door

Pick **one** tier. Do not do both unless you want Funnel as a backup URL.

Who can run what:

- Putting files in `www/`: that unix user (you).
- **Tier 0** script: Mini **owner** only (`sudo`, Tailscale CLI).
- **Tier 1** Cloudflare token: the person who owns the domain. One `sudo` from the Mini owner to install the LaunchDaemon.

### Tier 0 — no real domain (Funnel)

Public URLs:

- Root: `https://mini.<tailnet>.ts.net:8443/<your-name>/`
- A folder: `https://mini.<tailnet>.ts.net:8443/<your-name>/<sitename>/`

1. Owner runs once per user: `sudo ./scripts/enable-public-www.sh <shortname>`
2. If the script prints a browser link, open it and approve Funnel (first time this tailnet uses Funnel).
3. Test: On a phone with Tailscale **off**, open the public URL. You should see `www/`. While Tailscale is off the private site on port 443 will not load.

Optional: at your registrar, **URL-forward** `example.com` to that Funnel URL. After the click the address bar shows `ts.net`.

This Funnels only `/Users/<shortname>/www` on port **8443**. Port **443** stays private. Serve and Funnel cannot share a port.

### Tier 1 — `https://example.com` (Cloudflare Tunnel)

The tunnel points at the whole `www/`, so **by default** one domain has paths: `example.com/`, `example.com/photos/`.

1. You need a domain on Cloudflare (nameservers pointed at Cloudflare) and a free Cloudflare account. Each person uses **their** account. The Mini owner does not keep the renter’s token.
2. In Cloudflare, create an API token that can manage named tunnels and DNS.
3. On the Mini, as **that unix user** (not root): `./scripts/setup-cloudflared.sh example.com`
4. Paste the token when asked. The Mini owner types sudo once so the tunnel starts at boot.
5. On a phone with Tailscale **off**, open `https://example.com/`. The private site on port 443 must still require Tailscale.

Cloudflare terminates TLS and can see this public HTML. `~/srv` is not in the tunnel.

A named tunnel can only proxy HTTP, so the script starts a loopback static server (`scripts/lib/serve-static.py`) bound to `127.0.0.1`. Funnel does not need that process.

#### Two domains, two folders (still one tunnel)

You want `example.com` to be one site (as the site root, not `/sitename/`) and `anotherexample.com` to be another.

That is still Tier 1. You do **not** run Funnel per folder. You add hostnames to the **same** Cloudflare tunnel, each hostname rooted at one folder:

```
./scripts/setup-cloudflared.sh example.com=hello anotherexample.com=photos
```

Then:

| Folder | Public URL |
| --- | --- |
| `~/www/hello/index.html` | `https://example.com/` |
| `~/www/photos/index.html` | `https://anotherexample.com/` |

Both domains must sit on **that user’s** Cloudflare account (same tunnel). A later `mkdir ~/www/blog` is only on `example.com/blog` if you did not give blog its own hostname; to attach `blog.com`, run the script again with an extra `blog.com=blog` pair. Same tunnel, no second `cloudflared` process.

If the two domains are on **different** Cloudflare accounts, that is two tunnels and two tokens. Avoid it unless you have to.

Tier 0 cannot do this: Funnel is one `*.ts.net` host with paths. You can URL-forward `example.com` → `…/hello/` and `anotherexample.com` → `…/photos/`, but the address bar will still show `ts.net`.

## Do not

Do not port-forward 80/443 on the home router. Do not Funnel port 443. Do not put `srv/` under `www/`.
