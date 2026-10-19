#!/usr/bin/env bash
#
# capture.sh — snapshot this MacBookPro14,3's hardware fixes, dotfiles and package
#              list into the kit, so install.sh can rebuild the same setup anywhere.
#
# Usage:    ./capture.sh            (no root needed; rerun whenever you change a fix)
#
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
ROOTFS="$KIT/rootfs"
DOT="$KIT/dotfiles"
PKG="$KIT/packages"

log() { printf '\033[1;34m[capture]\033[0m %s\n' "$*"; }

# System files that make the hardware work. Paths are mirrored under rootfs/.
SYSTEM_FILES=(
    # Wi-Fi (BCM43602): real NVRAM, tx power, NetworkManager power save
    "/lib/firmware/brcm/brcmfmac43602-pcie.Apple Inc.-MacBookPro14,3.txt"
    /etc/systemd/system/wifi-txpower.service
    /etc/NetworkManager/conf.d/wifi-powersave.conf
    # Keyboard / Touch Bar (applespi + apple-ibridge)
    /etc/modprobe.d/apple_ib_tb.conf
    /etc/modprobe.d/applespi.conf
    /etc/modprobe.d/touchbar-no-sensorhub.conf
    /etc/modules-load.d/touchbar.conf
    /etc/modules-load.d/applespi.conf
    /etc/systemd/system/touchbar-fix.service
    /etc/udev/rules.d/99-touchbar-no-autosuspend.rules
    # NVMe power
    /etc/udev/rules.d/90-macbook-nvme-d3cold.rules
    # Lid close -> standby (kernel suspend hangs on this machine)
    /usr/local/sbin/mbp-suspend-fix
    /etc/systemd/system/mbp-lid-standby.service
    /etc/systemd/sleep.conf.d/mbp.conf
    /etc/systemd/logind.conf.d/mbp-lid.conf
    /etc/UPower/UPower.conf
)

# Dotfiles, relative to $HOME. Secrets (ssh, gh, tokens, browser profiles) are never taken.
DOTFILES=(
    .bashrc .profile .Xresources .gitconfig
    .config/i3 .config/i3blocks .config/i3status .config/terminator .config/nvim
    .config/autostart .config/nitrogen .config/xsettingsd .config/gtk-3.0
)

log "System files -> rootfs/"
rm -rf "$ROOTFS"
for f in "${SYSTEM_FILES[@]}"; do
    if [[ -e $f ]]; then
        mkdir -p "$ROOTFS$(dirname "$f")"
        cp -a "$f" "$ROOTFS$f"
    else
        log "  skip (missing) $f"
    fi
done

log "Dotfiles -> dotfiles/"
rm -rf "$DOT" && mkdir -p "$DOT"
for f in "${DOTFILES[@]}"; do
    [[ -e $HOME/$f ]] || continue
    mkdir -p "$DOT/$(dirname "$f")"
    cp -a "$HOME/$f" "$DOT/$f"
done
find "$DOT" -name '*.bak*' -delete

log "Package lists -> packages/"
mkdir -p "$PKG"
apt-mark showmanual | sort > "$PKG/apt-manual.txt"
# name channel classic(yes/no); skip bases and snapd itself
snap list --unicode=never 2>/dev/null | awk 'NR>1 && $NF !~ /base/ && $1 != "snapd" {
    classic = ($NF ~ /classic/) ? "yes" : "no"
    split($4, t, "/"); ch = (t[2] != "") ? t[2] : "stable"
    print $1, ch, classic }' > "$PKG/snaps.txt"

log "Touch Bar driver source -> dkms/macbook12-spi-driver/ (vendored for offline installs)"
SPI="$KIT/dkms/macbook12-spi-driver"
# Plain files, no nested .git, so the kit can be committed to the parent repo.
if [[ ! -f $SPI/apple-ibridge.c ]]; then
    tmp=$(mktemp -d)
    git clone -q https://github.com/roadrunner2/macbook12-spi-driver.git "$tmp/src"
    git -C "$tmp/src" checkout -q "$(cat "$KIT/dkms/macbook12-spi-driver.commit")"
    rm -rf "$tmp/src/.git" && mkdir -p "$SPI" && cp -a "$tmp/src/." "$SPI/" && rm -rf "$tmp"
fi
cp "$KIT/dkms/macbook12-spi-driver.dkms.conf" "$SPI/dkms.conf"
mkdir -p "$SPI/patches" && cp "$KIT"/dkms/patches/*.patch "$SPI/patches/"

log "Done. $(find "$ROOTFS" -type f | wc -l) system files, $(find "$DOT" -type f | wc -l) dotfiles,"
log "$(wc -l < "$PKG/apt-manual.txt") apt packages, $(wc -l < "$PKG/snaps.txt") snaps."
