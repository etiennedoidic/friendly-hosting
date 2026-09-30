# Acceptance tests for friendly-hosting

These are the checks that mean this component is done. They are stopwatch
and curl tests, not unit tests. Run them on the real Mini with a real
friend’s phone.

While developing scripts, run `tests/check-serve.sh` on a laptop (no Mini,
no Funnel). That covers index.html and MIME types against the fixtures.

## 1. Fresh Mini to installed site — under 60 minutes wall clock

What will happen: start from a Mini that is not yet on Tailscale. Follow
`docs/owner.md` including HUMAN steps, then hand the friend `docs/renter.md`.
Pass if, in under an hour including their time, their phone shows the
placeholder private site in standalone mode (no Safari chrome) after Add to
Home Screen. Fail if you had to install nginx, Caddy, or Docker, or if you
used the App Store Tailscale on the Mini.

Write down the actual minutes and which HUMAN steps ate them.

## 2. Second renter — under 5 minutes

What will happen: run `scripts/invite-renter.sh` with a new short name.
Do not rerun owner-init. Pass if that person (or you, on a second Tailscale
account) can accept a new share link and open
`https://mini.<tailnet>.ts.net/<new-renter>/` and see their own
copy of the placeholder, not the first renter’s path.

## 3. Public www from a phone that is not on the tailnet

What will happen: run `enable-public-www.sh` for one user, then open the
printed Funnel URL in cellular Safari with Tailscale off. Pass if the
placeholder `www/` loads. Then, if you are testing Tier 1, run
`setup-cloudflared.sh` and open `https://example.com/` the same way.
Pass if the address bar stays on your domain.

Fail if the private site (`srv` on port 443) is reachable on that public
URL. Fail if you port-forwarded the home router. A second folder under
`www/` should load without running the script again.

## 4. Isolation you can feel

What will happen: as renter A, try to fetch `/<renter-b>/`. Friend-grade
is enough: their home directory is mode 700 so files are not readable on
disk; path guessing on Serve may still show B’s placeholder HTML because
Serve is one node. Write down what actually happens. If Serve exposes
every --set-path to every shared user, say so in renter.md instead of
pretending Unix users hide the URL space.

## 5. Directory Serve MIME / index.html

Run `tests/check-serve.sh` (local) and, on Homebrew Tailscale,
`tests/check-serve.sh --tailscale`. Attach the PASS/FAIL lines here. If
MIME or index.html fails on Tailscale, the loopback static server
(`scripts/lib/serve-static.py`) is the allowed exception.

Boot once with App Store Tailscale only (no Homebrew) and paste whether
directory Serve/Funnel works. The owner doc should still name one variant
when you are done.

## 6. SSH stays inside that user

What will happen: renter follows the SSH section in `docs/renter.md`.
Owner passes `--ssh-key` to `invite-renter.sh`. Pass if they can `ssh` in
with the full `*.ts.net` name, `pwd` is under `/Users/<renter>`, and
`sudo -n true` fails. Fail if they can read another renter’s home or if
Tailscale SSH (not OpenSSH) was required.
