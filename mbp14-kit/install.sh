#!/usr/bin/env bash
#
# install.sh — make a fresh Ubuntu 25.10 work on a MacBookPro14,3 in one step:
#              Wi-Fi (BCM43602 NVRAM), sound (cs8409 via DKMS), keyboard + Touch Bar
#              (apple-ibridge via DKMS), lid-close standby, display on the iGPU,
#              plus your dotfiles and apps.
#
# The AMD dGPU is never disabled: it stays available for compute (PRIME / Vulkan / OpenCL).
# Drivers are registered with DKMS, so they rebuild by themselves on every kernel update.
# Safe to rerun. Replaced files are backed up once to /var/backups/mbp14-kit.
#
# Usage:    sudo ./install.sh [--no-dotfiles] [--no-packages] [--user NAME] [--force]
#           Inside a Cubic / ISO chroot it detects the chroot and skips live-system steps.
#
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd -P)"   # -P: /opt/mbp14-kit is a symlink
REPO="$(dirname "$KIT")"                       # snd_hda_macbookpro checkout
BACKUP_DIR=/var/backups/mbp14-kit
SUPPORTED_MODEL="MacBookPro14,3"
UNITS=(touchbar-fix.service wifi-txpower.service mbp-lid-standby.service)

SND_NAME=snd_hda_macbookpro   SND_VER=0.1
SPI_NAME=macbook12-spi-driver SPI_VER=0.1

DO_DOTFILES=1 DO_PACKAGES=1 FORCE=0
TARGET_USER=${SUDO_USER:-}

log()  { printf '\033[1;34m[mbp14-kit]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[mbp14-kit] WARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[mbp14-kit] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-dotfiles) DO_DOTFILES=0 ;;
        --no-packages) DO_PACKAGES=0 ;;
        --user) TARGET_USER=$2; shift ;;
        --force) FORCE=1 ;;
        *) die "Unknown option $1" ;;
    esac
    shift
done

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"

IN_CHROOT=0
systemd-detect-virt --chroot 2>/dev/null && IN_CHROOT=1

model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)
if [[ $model != "$SUPPORTED_MODEL" && $FORCE -eq 0 && $IN_CHROOT -eq 0 ]]; then
    die "This is a '$model', expected $SUPPORTED_MODEL (use --force to override)."
fi

# Kernels to build for: every installed kernel that has headers (in a chroot uname -r
# is the host kernel, so never rely on it there).
kernels() {
    local d
    for d in /lib/modules/*; do
        [[ -e $d/build/Makefile ]] && basename "$d"
    done
}

backup() {
    local f=$1
    [[ -e $f || -L $f ]] || return 0
    mkdir -p "$BACKUP_DIR$(dirname "$f")"
    [[ -e $BACKUP_DIR$f ]] || cp -a "$f" "$BACKUP_DIR$f"
}

# --- 1. packages needed by the fixes -------------------------------------------------

install_deps() {
    log "Installing build tools and helpers"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    apt-get install -y -q dkms build-essential patch git wget rsync python3 \
        linux-headers-generic brightnessctl i3lock xss-lock iw wireless-tools

    # Headers for every kernel present (an ISO's kernel can be older than -generic's).
    local k series
    for k in $(ls /lib/modules); do
        [[ -e /lib/modules/$k/build/Makefile ]] ||
            apt-get install -y -q "linux-headers-$k" || warn "no headers for $k"
    done

    # The cs8409 build patches the Ubuntu kernel source (linux-source-X.Y.0).
    for k in $(kernels); do
        series=$(cut -d- -f1 <<<"$k")
        dpkg -s "linux-source-$series" >/dev/null 2>&1 ||
            apt-get install -y -q "linux-source-$series" ||
            warn "linux-source-$series not available; sound may not build for $k"
    done
}

# --- 2. system files ------------------------------------------------------------

install_rootfs() {
    log "Copying system files from rootfs/"
    local src dst
    while IFS= read -r -d '' src; do
        dst=${src#"$KIT/rootfs"}
        backup "$dst"
        install -D -m "$(stat -c %a "$src")" "$src" "$dst"
    done < <(find "$KIT/rootfs" -type f -print0)
}

# --- 3. drivers through DKMS ---------------------------------------------------------

# Modules built by hand earlier sit next to the DKMS ones and could shadow them.
# Only called once DKMS has installed its own copy for that kernel.
remove_handbuilt() {   # kernel name
    local k=$1 f files
    case $2 in
        "$SND_NAME") files=(/lib/modules/$k/updates/codecs/cirrus/snd-hda-codec-cs8409.ko) ;;
        "$SPI_NAME") files=(/lib/modules/$k/updates/apple-ib{ridge,-tb,-als}.ko) ;;
    esac
    for f in "${files[@]}"; do
        [[ -e $f ]] || continue
        log "Moving hand-built $(basename "$f") ($k) to $BACKUP_DIR"
        backup "$f"
        rm -f "$f"
    done
}

dkms_register() {   # name version source-dir
    local name=$1 ver=$2 src=$3 dst="/usr/src/$1-$2"
    # An older setup symlinked /usr/src to a checkout in $HOME; use a real copy instead.
    [[ -L $dst ]] && { backup "$dst"; rm -f "$dst"; }
    mkdir -p "$dst"
    rsync -a --delete --exclude .git --exclude build --exclude mbp14-kit "$src/" "$dst/"
    dkms status -m "$name" -v "$ver" 2>/dev/null | grep -q . || dkms add -m "$name" -v "$ver"
    local k
    for k in $(kernels); do
        log "DKMS: building $name for $k"
        if dkms install -m "$name" -v "$ver" -k "$k" --force; then
            remove_handbuilt "$k" "$name"
        else
            warn "$name failed to build for $k (see /var/lib/dkms/$name/$ver/build/make.log)"
        fi
    done
}

install_drivers() {
    dkms_register "$SND_NAME" "$SND_VER" "$REPO"

    local spi="$KIT/dkms/macbook12-spi-driver"
    if [[ ! -d $spi ]]; then
        log "Fetching Touch Bar driver source"
        git clone -q https://github.com/roadrunner2/macbook12-spi-driver.git "$spi"
        git -C "$spi" checkout -q "$(cat "$KIT/dkms/macbook12-spi-driver.commit")"
    fi
    cp "$KIT/dkms/macbook12-spi-driver.dkms.conf" "$spi/dkms.conf"
    mkdir -p "$spi/patches" && cp "$KIT"/dkms/patches/*.patch "$spi/patches/"
    dkms_register "$SPI_NAME" "$SPI_VER" "$spi"

    local k
    for k in $(kernels); do depmod -a "$k"; done
}

# --- 4. services, GPU, groups ---------------------------------------------------------

enable_units() {
    log "Enabling ${UNITS[*]}"
    systemctl enable "${UNITS[@]}" >/dev/null
    # Old reset services from earlier attempts race with touchbar-fix.
    local svc
    for svc in macbook-touchbar touchbar-usb-fix macbook-suspend mbp-suspend-fix; do
        [[ -e /etc/systemd/system/$svc.service ]] || continue
        backup "/etc/systemd/system/$svc.service"
        systemctl disable "$svc.service" >/dev/null 2>&1 || true
        rm -f "/etc/systemd/system/$svc.service"
    done
    if [[ $IN_CHROOT -eq 0 ]]; then
        systemctl daemon-reload
        systemctl kill -s HUP systemd-logind.service || true
        systemctl try-restart upower.service || true
        systemctl restart mbp-lid-standby.service || true
    fi
}

# Apple's gmux: route the internal display through the Intel iGPU. The setting lives in
# NVRAM, so it survives reinstalls; it only picks the display GPU, amdgpu still loads.
set_gpu_pref() {
    [[ $IN_CHROOT -eq 1 ]] && return 0
    local var=/sys/firmware/efi/efivars/gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9
    [[ -d /sys/firmware/efi/efivars ]] || return 0
    if [[ -e $var ]]; then
        log "gpu-power-prefs already set ($(od -An -tx1 "$var" | tr -s ' '))"
        return 0
    fi
    log "Setting gpu-power-prefs: display on the iGPU (dGPU stays on for compute)"
    printf '\x07\x00\x00\x00\x01\x00\x00\x00' > "$var"
}

setup_user() {
    [[ -n $TARGET_USER ]] || TARGET_USER=$(getent passwd 1000 | cut -d: -f1)
    [[ -n $TARGET_USER ]] || { warn "No user found; skipping groups and dotfiles"; return 0; }
    log "Adding $TARGET_USER to video,input (brightness keys)"
    usermod -aG video,input "$TARGET_USER"

    [[ $DO_DOTFILES -eq 1 && -d $KIT/dotfiles ]] || return 0
    local home
    home=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    log "Restoring dotfiles into $home (existing files get a .pre-mbp14 copy)"
    local src rel
    while IFS= read -r -d '' src; do
        rel=${src#"$KIT/dotfiles/"}
        if [[ -e $home/$rel && ! -e $home/$rel.pre-mbp14 ]] && ! cmp -s "$src" "$home/$rel"; then
            cp -a "$home/$rel" "$home/$rel.pre-mbp14"
        fi
        runuser -u "$TARGET_USER" -- install -D -m "$(stat -c %a "$src")" "$src" "$home/$rel"
    done < <(find "$KIT/dotfiles" -type f -print0)
}

install_packages() {
    [[ $DO_PACKAGES -eq 1 ]] || return 0
    local list="$KIT/packages/apt-manual.txt"
    if [[ -s $list ]]; then
        log "Installing apt packages from packages/apt-manual.txt"
        # Only names this release knows; unknown or renamed ones are skipped, not fatal.
        comm -12 <(sort -u "$list") <(apt-cache pkgnames | sort -u) |
            xargs -r apt-get install -y -q --no-install-recommends ||
            warn "Some apt packages failed; rerun with --no-packages to skip"
    fi
    list="$KIT/packages/snaps.txt"
    if [[ -s $list ]] && command -v snap >/dev/null; then
        log "Installing snaps from packages/snaps.txt"
        local name ch classic
        while read -r name ch classic; do
            snap list "$name" >/dev/null 2>&1 && continue
            local opts=(--channel="$ch")
            [[ $classic == yes ]] && opts+=(--classic)
            snap install "$name" "${opts[@]}" || warn "snap $name failed"
        done < "$list"
    fi
}

finish() {
    if [[ $IN_CHROOT -eq 0 ]]; then
        update-initramfs -u -k all
    else
        local k
        for k in $(kernels); do update-initramfs -u -k "$k"; done
    fi
    log "Done. Reboot, then check:"
    log "  dkms status                     -> both drivers 'installed'"
    log "  speaker-test -c2 -t wav -l1     -> sound"
    log "  Touch Bar shows F-keys, Fn for media; Wi-Fi sees 5 GHz networks"
    log "  close the lid -> screen locks;  journalctl -t mbp-lid-standby"
}

install_deps
install_rootfs
install_drivers
enable_units
set_gpu_pref
if [[ $IN_CHROOT -eq 1 ]]; then
    # No users and no snapd in the ISO chroot: mbp14-firstboot.service does these on
    # the first boot of the installed system.
    log "Chroot: skipping user groups, dotfiles and packages (done at first boot)"
else
    setup_user
    install_packages
fi
finish
