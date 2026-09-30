# Appendix: invite the renter onto your tailnet

Default for friends is **device share** (`docs/renter.md`). Use this appendix only when the renter has no Tailscale account yet and you want them on your Personal tailnet as a member (Tailscale’s personal plan allows a small number of users; check the current seat count before you promise).

Why it is not the default: a member of your tailnet is a peer on the network the Mini lives on. A share only shows them the Mini. Also, one login cannot be in two tailnets, so a renter who already has Tailscale cannot join yours with that same login.

## What will happen if you choose this

1. Run `owner-init.sh` first so the restrictive ACL is already live: shared-or-member traffic to the Mini is 443 (and 22 if you open it), not `*:*`.
2. In the admin console (or later, if we add it to the API helper), invite the person as a **Member**, not Admin.
3. They install Tailscale, accept the user invite, and open the same `https://mini.<tailnet>.ts.net/<renter>/` URL. No device-share link.
4. They can still be a macOS user on the Mini with home mode 700. Unix isolation does not change. SSH, if they want it, is the same as in `docs/renter.md`: their public key, OpenSSH on port 22, no sudo.

If you already shared the node and then invite them as a user, remove the device share so you have one story, not two.
