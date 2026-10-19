# mbp14-kit: plug-and-play Ubuntu 25.10 on a MacBookPro14,3

Everything that makes this Mac work on Linux, in one place:

| Problem | Fix in the kit |
|---|---|
| Wi-Fi (BCM43602) sees few networks, no 5 GHz | real NVRAM in `rootfs/lib/firmware/brcm/`, `wifi-txpower.service`, NM power save off |
| No speakers / headphones (CS8409) | `snd_hda_macbookpro` (this repo) as **DKMS** |
| Keyboard, Touch Bar, light sensor | `macbook12-spi-driver` (ported to 6.17, `dkms/patches/`) as **DKMS** + modprobe/udev/`touchbar-fix.service` |
| Closing the lid freezes the Mac | `mbp-lid-standby.service`: lock + screen off, no kernel suspend |
| Brightness keys | user added to `video,input`; i3 bindings in dotfiles |
| Hot / noisy dGPU | `gpu-power-prefs` EFI var puts the display on the iGPU; **amdgpu stays on for compute** |

DKMS rebuilds both drivers on every kernel update, so they no longer break after `apt upgrade`.

## Layout

```
install.sh     sudo ./install.sh [--no-dotfiles] [--no-packages] [--user NAME]
capture.sh     ./capture.sh: re-snapshot this machine's configs into the kit
rootfs/        system files, same paths as on /
dkms/          Touch Bar driver source + dkms.conf + 6.17 patch
dotfiles/      i3, i3blocks, i3status, terminator, nvim, gtk, .bashrc ...
packages/      apt-manual.txt, snaps.txt
iso/           Cubic chroot script + first-boot service
```

## A. Fresh stock Ubuntu install

```bash
git clone https://github.com/jero98772/snd_hda_macbookpro.git
cd snd_hda_macbookpro/mbp14-kit
sudo ./install.sh          # needs internet (USB tether / dongle if Wi-Fi isn't up yet)
sudo reboot
```

## B. Custom ISO (Wi-Fi, keyboard and sound already work in the installer)

1. Install Cubic:
   `sudo apt-add-repository ppa:cubic-wizard/release && sudo apt install cubic`
2. Download `ubuntu-25.10-desktop-amd64.iso`, open Cubic and choose a project folder such as `~/iso/mbp14`.
3. When Cubic reaches its **chroot terminal**, drag the `snd_hda_macbookpro` folder into the window (Cubic copies it into the chroot), then run:
   ```bash
   bash snd_hda_macbookpro/mbp14-kit/iso/cubic-chroot.sh
   ```
   That builds the drivers for the ISO's kernel, installs every fix and enables `mbp14-firstboot.service`.
4. Click Next through the remaining steps and **Generate**. You get `~/iso/mbp14/ubuntu-25.10-*-custom.iso`.
5. Write it to a USB stick: `sudo dd if=<iso> of=/dev/sdX bs=4M status=progress oflag=sync`.
   Boot the Mac with **Option (⌥)** held and pick "EFI Boot".

On the first boot after installing, `mbp14-firstboot.service` adds your user to `video,input`, restores the dotfiles and reinstalls your apt and snap apps. Follow it with `journalctl -u mbp14-firstboot -f`.

## Keeping it up to date

When you change a fix on the machine, run `./capture.sh` and commit. Rebuild the ISO only when you want a new base release.

## Checks after a reboot

```bash
dkms status                          # snd_hda_macbookpro + macbook12-spi-driver: installed
speaker-test -c2 -t wav -l1          # sound
iw phy phy0 info | grep 'Band 2'     # 5 GHz present
journalctl -t mbp-lid-standby        # lid close / open events
```

Notes: the Wi-Fi NVRAM file carries this Mac's MAC address. Secrets (`~/.ssh`, `gh` tokens, browser profiles) are never captured.
