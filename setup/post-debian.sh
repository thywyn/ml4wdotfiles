#!/usr/bin/env bash

# --------------------------------------------------------------
# Oh My Posh
# --------------------------------------------------------------
curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin

# --------------------------------------------------------------
# ML4W Settings App
#
# Upstream setup.sh has no Debian branch (pacman/dnf/zypper only),
# so we replicate it here: install deps via apt, clone, make install.
# --------------------------------------------------------------

info "Installing ML4W Dotfiles Settings dependencies (Debian)..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends git make jq gawk gum

ML4W_SETTINGS_TMP=$(mktemp -d -t ml4w-dotfiles-settings-XXXXXX)
info "Cloning ML4W Dotfiles Settings into $ML4W_SETTINGS_TMP..."
git clone --depth=1 https://github.com/mylinuxforwork/ml4w-dotfiles-settings.git "$ML4W_SETTINGS_TMP"
make -C "$ML4W_SETTINGS_TMP" install
rm -rf "$ML4W_SETTINGS_TMP"

if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
    if [[ -f "$HOME/.bashrc" ]] && ! grep -q ".local/bin" "$HOME/.bashrc"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
fi

# --------------------------------------------------------------
# Cargo (matugen, awww)
#
# Binaries are built under a temporary --root, then installed to
# /usr/local/bin so they are on the PATH for every user session
# — including Hyprland's exec-once environment, which does NOT
# include ~/.cargo/bin or ~/.local/bin by default.
# --------------------------------------------------------------

MATUGEN_TARGET="4.0.0"

CARGO_BUILD_ROOT="$(mktemp -d -t cargo-build-XXXXXX)"
trap 'rm -rf "$CARGO_BUILD_ROOT"' EXIT

# Migrate any pre-existing cargo-installed copies from ~/.cargo/bin to
# /usr/local/bin so they are visible to Hyprland's exec-once PATH. The
# old copies are removed afterward to avoid two versions on PATH.
migrate_cargo_bin() {
    local b src="$HOME/.cargo/bin"
    for b in "$@"; do
        if [ -x "$src/$b" ] && [ ! -e "/usr/local/bin/$b" ]; then
            info "Migrating $b from $src to /usr/local/bin (sudo)..."
            sudo install -m 0755 "$src/$b" "/usr/local/bin/$b"
        fi
        if [ -e "$src/$b" ] && [ -x "/usr/local/bin/$b" ]; then
            info "Removing stale $src/$b (now provided by /usr/local/bin)."
            rm -f "$src/$b"
        fi
    done
}

migrate_cargo_bin matugen awww awww-daemon

cargo_install_system() {
    # Usage: cargo_install_system <log-label> -- <cargo install args...>
    local label="$1"; shift
    [ "$1" = "--" ] && shift
    info "Building $label via cargo (temp root: $CARGO_BUILD_ROOT)..."
    cargo install --root "$CARGO_BUILD_ROOT" "$@"
}

install_built_bins() {
    # Usage: install_built_bins <bin> [<bin>...]
    local b
    for b in "$@"; do
        if [ ! -x "$CARGO_BUILD_ROOT/bin/$b" ]; then
            error "Expected binary $b not found after build."
            return 1
        fi
        info "Installing $b to /usr/local/bin (sudo)..."
        sudo install -m 0755 "$CARGO_BUILD_ROOT/bin/$b" "/usr/local/bin/$b"
    done
}

force_install_matugen() {
    cargo_install_system matugen -- matugen --force
    install_built_bins matugen
}

if ! command -v matugen &> /dev/null; then
    info "matugen is not installed. Installing..."
    force_install_matugen
else
    CURRENT=$(matugen --version | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    LOWEST=$(printf "%s\n%s" "$MATUGEN_TARGET" "$CURRENT" | sort -V | head -n1)
    if [ "$LOWEST" = "$CURRENT" ] && [ "$CURRENT" != "$MATUGEN_TARGET" ]; then
        info "matugen $CURRENT < $MATUGEN_TARGET, updating..."
        force_install_matugen
    else
        info "matugen $CURRENT is up to date."
    fi
fi

if ! command -v awww &> /dev/null; then
    info "Installing awww + awww-daemon via cargo (codeberg source)..."
    cargo_install_system awww -- --git https://codeberg.org/LGFae/awww awww awww-daemon
    install_built_bins awww awww-daemon
else
    info "awww already installed."
fi

# --------------------------------------------------------------
# pywalfox via pipx (PEP 668 makes pip install --user unreliable on
# Debian; pipx is the supported path)
# --------------------------------------------------------------

if ! command -v pywalfox &> /dev/null; then
    info "Installing pywalfox via pipx..."
    pipx install pywalfox
    pipx ensurepath
else
    info "pywalfox already installed."
fi

# --------------------------------------------------------------
# Nerd Fonts (FiraCode, JetBrainsMono) — not packaged in Debian.
# Pull from upstream release tarballs.
# --------------------------------------------------------------

NERD_VER="${NERD_FONTS_VERSION:-v3.4.0}"
NERD_TMP=$(mktemp -d)
NERD_DEST="/usr/share/fonts/nerd-fonts"

install_nerd_font() {
    local name=$1
    local url="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_VER}/${name}.tar.xz"
    info "  - Downloading ${name} ${NERD_VER}"
    if ! curl -fsSL -o "$NERD_TMP/${name}.tar.xz" "$url"; then
        warn "  - Failed to download ${name}; skipping"
        return 1
    fi
    sudo mkdir -p "$NERD_DEST/${name}"
    sudo tar -xf "$NERD_TMP/${name}.tar.xz" -C "$NERD_DEST/${name}"
}

info "Installing Nerd Fonts (${NERD_VER})..."
install_nerd_font "FiraCode"
install_nerd_font "JetBrainsMono"
sudo fc-cache -f
rm -rf "$NERD_TMP"

# --------------------------------------------------------------
# Font Awesome 7 Free
#
# Debian's `fonts-font-awesome` package is actually FA 4.7 (the
# `5.0.10+really4.7.0` version string is misleading). ML4W's waybar
# modules.json uses codepoints introduced in FA 6/7 — e.g. U+F5FD
# (screwdriver-wrench/Tools), U+E4DC, U+E473 — that exist in
# `Font Awesome 7 Free Solid` and nowhere else in the Nerd Font
# patches we install. Pull FA 7 from upstream so those glyphs render.
# --------------------------------------------------------------

FA_VER="${FONT_AWESOME_VERSION:-7.1.0}"
FA_DEST="/usr/share/fonts/font-awesome-7"
if [ ! -d "$FA_DEST" ]; then
    info "Installing Font Awesome ${FA_VER} Free..."
    FA_TMP=$(mktemp -d)
    if curl -fsSL -o "$FA_TMP/fa.zip" \
        "https://github.com/FortAwesome/Font-Awesome/releases/download/${FA_VER}/fontawesome-free-${FA_VER}-desktop.zip"; then
        (cd "$FA_TMP" && unzip -q fa.zip)
        sudo mkdir -p "$FA_DEST"
        sudo cp "$FA_TMP/fontawesome-free-${FA_VER}-desktop/otfs/"*.otf "$FA_DEST/"
        sudo fc-cache -f
    else
        warn "  - Failed to download Font Awesome ${FA_VER}; waybar icons may not render"
    fi
    rm -rf "$FA_TMP"
else
    info "Font Awesome 7 already installed."
fi

# --------------------------------------------------------------
# Grimblast (vendored script in the dotfiles repo)
# --------------------------------------------------------------

if [ -f "$repo_path/setup/scripts/grimblast" ]; then
    sudo cp "$repo_path/setup/scripts/grimblast" /usr/bin/grimblast
    sudo chmod +x /usr/bin/grimblast
fi

# --------------------------------------------------------------
# Cursors / fonts / icons
# --------------------------------------------------------------

source "$repo_path/setup/_cursors.sh"
source "$repo_path/setup/_fonts.sh"
source "$repo_path/setup/_icons.sh"

# --------------------------------------------------------------
# XDG user dirs
# --------------------------------------------------------------

xdg-user-dirs-update

# --------------------------------------------------------------
# System services
#
# Debian doesn't enable upower on install; without it wireplumber
# logs "Failed to get percentage from UPower: NameHasNoOwner" at
# every session start.
# --------------------------------------------------------------

sudo systemctl enable --now upower.service
