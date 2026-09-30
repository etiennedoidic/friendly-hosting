# Renter setup

The owner of the Mini can read the files in your account. This is a friend’s computer, not a bank vault. If that is not acceptable, do not put private material here.

You get a macOS user on their Mini. You are not an admin. You cannot `sudo`, install Homebrew packages for the whole machine, or see other people’s homes. You can work in `/Users/<your-name>/`, including `~/srv` (private site) and `~/www` (public static files).

## Getting access to a site on your phone

Target: about 10 minutes.

1. **HUMAN — Install Tailscale on your phone.** App Store or Play Store. Sign in with whatever account you already use for Tailscale, or create one.

2. **HUMAN — Tap the share link the owner sent.** It is a Tailscale invite, not the website URL. Accept it. After this, one machine named something like `mini` appears in your Tailscale app.

3. **HUMAN — Open the website URL they sent.** It might look like `https://mini.<something>.ts.net/<your-name>/`. Tailscale on the phone must be on. If the page fails, the share was not accepted or Tailscale is off.

4. **HUMAN — Add to Home Screen.**
   - iPhone: Share button in Safari → Add to Home Screen.
   - Android Chrome: menu → Install app / Add to Home Screen.

## SSH, if you want to build on the Mini

SSH gives you access to your home directory to build whatever you want there. Shared machines do not support Tailscale SSH; this is ordinary `ssh` over the tailnet to port 22.

1. **HUMAN — Install Tailscale on your local device** if it is not there. Sign in as the same user that accepted the share. Turn Tailscale on. Confirm `mini` (or whatever they named it) appears.

2. **HUMAN — Make a key and send only the public half to the owner.** Never send the file that has no `.pub` suffix.

   Run this to make the key:

   ```
   ssh-keygen -t ed25519 -f ~/.ssh/mini -C "<your-name>@mini"
   ```

   Then send the owner the contents of `~/.ssh/mini.pub` (one line starting with `ssh-ed25519`). Also tell them your renter short name if they do not already have it.

3. Wait until the owner says your key is installed. They will run `invite-renter.sh` on the Mini and pass in your `.pub` file. If they already created your account when they first invited you, they run that same owner script again, this time only to add the key.

4. **HUMAN — Log in.** Use the Mini’s full Tailscale name (required for a shared machine), your macOS short name, and the key you just made:

   ```
   ssh -i ~/.ssh/mini <your-name>@mini.<their-tailnet>.ts.net
   ```

   The owner can give you the exact host string; it matches the hostname in the private URL. Success is a prompt in `/Users/<your-name>`. `Permission denied (publickey)` means the key is not installed yet or you pointed `ssh` at the wrong key. `Could not resolve host` means Tailscale is off or you used the short name `mini` instead of the full `*.ts.net` name.

5. **Work only as yourself.** `pwd` should be under `/Users/<your-name>`. Put private project files in `~/srv` or elsewhere in that home. `sudo` will fail; that is correct. Do not try to `brew install` into `/opt/homebrew` — that belongs to the owner. Use the system git/compiler already on the Mini, and install language tools into your home (`nvm`, `rustup`, `pip --user`, and so on). You cannot reboot the Mini or change other users. If something outside your home is broken, message the owner.

6. **Optional — Type `ssh mini` instead of the long command.** On the **laptop**, append this to `~/.ssh/config` (create the file if it does not exist). Use the same host and user that worked in step 4:

   ```
   Host mini
     HostName mini.<their-tailnet>.ts.net
     User <your-name>
     IdentityFile ~/.ssh/mini
   ```

   Then `ssh mini` is enough. Tailscale still has to be on. You can change `Host mini` to any short name you like.

## Public static sites

Once you have SSH you can develop public static websites. Put HTML in `~/www/` (each site is a folder). The owner turns Funnel on once with `enable-public-www.sh <your-name>`. A real domain is `docs/domain.md`. Do not put any private files or sensitive data in `www/`.

## What you cannot do

You cannot see other renters’ files (their homes are mode 700). You cannot reset the Mini. You cannot become admin.
