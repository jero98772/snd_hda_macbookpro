#!/usr/bin/env bash
#
# cubic-chroot.sh — run inside Cubic's chroot terminal, after copying the kit in:
#     (drag the snd_hda_macbookpro folder into Cubic's terminal, it lands in the cwd)
#     bash snd_hda_macbookpro/mbp14-kit/iso/cubic-chroot.sh
#
# Bakes every MacBookPro14,3 fix into the ISO: the live session already has Wi-Fi,
# keyboard, Touch Bar and sound, and the installed system inherits all of it. On the
# first boot of the installed system mbp14-firstboot.service adds the user to the
# video/input groups and restores dotfiles and apps.
#
set -euo pipefail

SRC="$(cd "$(dirname "$0")/../.." && pwd)"     # snd_hda_macbookpro checkout
DST=/opt/snd_hda_macbookpro

echo "[cubic] Copying kit to $DST"
rm -rf "$DST"
mkdir -p "$DST"
cp -a "$SRC/." "$DST/"
rm -rf "$DST/.git" "$DST/build"
ln -sfn "$DST/mbp14-kit" /opt/mbp14-kit

echo "[cubic] Installing fixes and building drivers for: $(ls /lib/modules)"
/opt/mbp14-kit/install.sh

install -m 0644 /opt/mbp14-kit/iso/mbp14-firstboot.service /etc/systemd/system/
systemctl enable mbp14-firstboot.service

apt-get clean
echo "[cubic] Done. dkms status:"
dkms status
