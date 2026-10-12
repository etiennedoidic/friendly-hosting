Use this when you want to share a Mac with people you trust: private files on your tailnet, a public www folder, and renter logins that cannot administer the machine.

On the Mini, run `scripts/prep-mini.sh` if it should stay awake, then `scripts/owner-init.sh`. Add a person with `scripts/invite-renter.sh`. You run these yourself; they create users and install services.

## Integrate

### macOS
1. Install Tailscale.
2. On the Mini, run `scripts/owner-init.sh`.
