# Owner setup

Every step a human must do is marked **HUMAN**. Everything else is a script. Do not skip the HUMAN lines; the scripts cannot log into Tailscale as you.

Use this document at the Mini, over Screen Sharing or with a keyboard attached for the first run. After `prep-mini.sh`, you should be able to finish from another computer over SSH.

## Before you start

You need: the Mini, a network connection, an Apple ID you already use on this Mac, and a browser.

## Steps

1. **HUMAN — Install Homebrew if it is not already there.** This takes a while (15-30 minutes): it downloads Xcode Command Line Tools, then Homebrew itself. Check first; skip the install if `brew` already works.

   ```
   which brew
   ```

   If that prints nothing, run:

   ```
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

   After the installer finishes, `brew` may still say “command not found.” On Apple Silicon Macs, Homebrew lives in `/opt/homebrew`, and the terminal does not look there until you tell it to. The first line below remembers that for every new terminal. The second line applies it in *this* terminal so you do not have to quit and reopen. Then `brew --version` should print a version number.

   ```
   echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
   eval "$(/opt/homebrew/bin/brew shellenv)"
   brew --version
   ```

2. **HUMAN — Create a Tailscale account.** In a browser, sign up at Tailscale if you don't already have an account.

3. **HUMAN — Install Homebrew Tailscale on the Mini.** `brew install --formula tailscale` and `sudo brew services start tailscale`. Do not also install the App Store Tailscale; that will cause issues. See `docs/client-variant.md`.

4. **HUMAN — Make one API access token.** Open [the Keys page](https://login.tailscale.com/admin/settings/keys) and click **Generate access token**. Set the expiry to 90 days (the maximum). Copy the key and keep it somewhere safe. You will paste it into `owner-init.sh` in step 6.

   That token is only for **setup and later admin scripts**.

   You would only need a token again to run `invite-renter.sh` or to change policy from a script. If it has expired, either generate a new one the same way, or add the renter by hand: Machines → the Mini → **Share**.

5. **HUMAN — Run the prep script (Mini only).** From this folder: `sudo ./scripts/prep-mini.sh`. This keeps the Mini awake, turns on SSH, warns you about FileVault, and makes sure `/Library/LaunchDaemons` exists. Skip this on a laptop: it turns sleep off. FileVault is never toggled by the script; if it is on, a power loss leaves the Mac at the disk-unlock screen until someone types the password.

6. **HUMAN — Run the owner script.** `sudo ./scripts/owner-init.sh`. It will ask for the API token from Step 4 and a hostname (default `mini`). The first renter’s short name is optional: press Return to skip if you do not have anyone to invite yet. You can add people later with `invite-renter.sh`.

   If you do enter a name, it becomes the macOS account and the URL path (`…ts.net/<name>/`). Rules: 1–31 characters, start with a lowercase letter, then only lowercase letters and digits.

   If that person also wants a shell so they can build on the Mini, ask them to follow the SSH section in `docs/renter.md` and send you a `.pub` file. Pass that file to `owner-init.sh` when it asks (or to `invite-renter.sh` later). Without a key they still get the private site; they cannot log in with a password.

7. **HUMAN if the script says so — Toggle HTTPS certificates.** If the API cannot enable tailnet HTTPS, the script will print a link to the DNS page. Flip HTTPS on. MagicDNS should already be on from the script.

8. **Confirm the Mini joined.** Run:

   ```
   tailscale status
   ```

   Success is a table. The first line is this Mac. It should look like this (IP, tailnet suffix, and extra peer rows will differ):

   ```
   100.64.1.2  mini  tagged-devices  macOS  -
   ```

   Read it as: a `100.` address (Tailscale IP), hostname `mini` or whatever you typed in step 6, owner `tagged-devices` (that means `tag:host` applied; you will not see your email on a tagged machine), OS `macOS`, and a status that is **not** `offline`. `Logged out.` or `stopped` means join failed; rerun step 6.

   If you passed a renter name, also run `tailscale serve status`. You should see a path `/<renter>/` pointing at that user’s `srv` folder (private site). Public files live in `www` and are not on this port. See `docs/domain.md` when you want them on the internet.

9. **If you created a renter, send them the invite.** Copy the share link and the private URL the owner script printed. Send both, plus a pointer to `docs/renter.md`. The URL looks like `https://mini.<your-tailnet>.ts.net/<renter>/`. If they want SSH, ask them to send you a public key; install it with `invite-renter.sh` if you did not already pass it in step 6. They log in as that macOS user only — not admin, not your account.

**Optional — Add a renter.** Adding a renter later, or a second one, is `invite-renter.sh`. Pass `--ssh-key path/to/their.pub` when they should be able to build in their home. You can run that again for an existing renter to add a key without creating a second user.

**Optional — Public static sites.** Same for you and renters after this setup: files go in that user’s `~/www/`. Turn the public door on following `docs/domain.md`.

## Privacy you are promising

As the owner you are the admin of this Mac. You can read renter files; they should be aware of that. We are not encrypting their disk against you.
