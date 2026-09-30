# shellcheck shell=sh

fh_random_password() {
	openssl rand -base64 24 | tr -d '\n'
}

# Do not overwrite an existing index.html (owner/renter content).
fh_copy_fixture_tree() {
	_src="$1"
	_dst="$2"
	mkdir -p "$_dst"
	if [ ! -f "$_dst/index.html" ] && [ -d "$_src" ]; then
		cp -R "$_src/." "$_dst/"
	fi
}

fh_init_home() {
	_name="$1"
	fh_user_exists "$_name" || fh_die "fh_init_home: no such user $_name"
	_home="$(fh_home "$_name")"
	_priv="$(fh_private_dir_for "$_name")"
	_pub="$(fh_public_dir_for "$_name")"
	_st="$(fh_state_dir_for "$_name")"

	chmod 700 "$_home" || true
	mkdir -p "$_priv" "$_pub" "$_st"
	fh_copy_fixture_tree "$FH_ROOT/fixtures/srv" "$_priv"
	fh_copy_fixture_tree "$FH_ROOT/fixtures/www" "$_pub"
	chown -R "$_name:staff" "$_priv" "$_pub" "$_st" 2>/dev/null || chown -R "$_name" "$_priv" "$_pub" "$_st"
	if command -v tmutil >/dev/null 2>&1; then
		tmutil addexclusion "$_st" >/dev/null 2>&1 || true
	fi
}

fh_add_renter() {
	_name="$1"
	fh_valid_shortname "$_name" || fh_die "short name must match ^[a-z][a-z0-9]{0,30}$ (got: $_name)"
	if fh_user_exists "$_name"; then
		echo "user $_name already exists; leaving the account as-is"
		fh_init_home "$_name"
		return 0
	fi
	_pw="$(fh_random_password)"
	echo "creating non-admin user $_name"
	sysadminctl -addUser "$_name" -fullName "$_name" -password "$_pw"
	unset _pw
	if command -v createhomedir >/dev/null 2>&1; then
		createhomedir -c -u "$_name" >/dev/null 2>&1 || true
	fi
	fh_user_exists "$_name" || fh_die "sysadminctl did not create $_name"
	chmod 700 "$(fh_home "$_name")"
	fh_init_home "$_name"
	echo "password login is not set up for $_name; they need an SSH public key to get a shell"
}

fh_install_ssh_key() {
	_name="$1"
	_keyfile="$2"
	[ -f "$_keyfile" ] || fh_die "SSH public key file not found: $_keyfile"
	_line="$(tr -d '\r' <"$_keyfile" | awk 'NF {print; exit}')"
	echo "$_line" | grep -Eq '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) ' \
		|| fh_die "$_keyfile does not look like an OpenSSH public key"
	_home="$(fh_home "$_name")"
	_ssh="$_home/.ssh"
	mkdir -p "$_ssh"
	touch "$_ssh/authorized_keys"
	if grep -Fqx "$_line" "$_ssh/authorized_keys" 2>/dev/null; then
		echo "that key is already in $_ssh/authorized_keys"
	else
		printf '%s\n' "$_line" >>"$_ssh/authorized_keys"
		echo "installed SSH key for $_name"
	fi
	chmod 700 "$_ssh"
	chmod 600 "$_ssh/authorized_keys"
	chown -R "$_name:staff" "$_ssh" 2>/dev/null || chown -R "$_name" "$_ssh"
}
