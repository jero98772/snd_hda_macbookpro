#!/bin/bash
# =====================================================================
# Fix internal Broadcom BCM43602 Wi-Fi (2.4 GHz only / won't connect)
# Machine: MacBookPro14,3 (A1707)  /  Ubuntu 25.10  /  iface wlp3s0
#
# Root cause (kernel bug 193121): the chip has no usable NVRAM, so the
#   linux-firmware blob falls back to its built-in generic NVRAM
#   (ccode=X0 regrev=15, MAC 00:90:4c:0d:f4:3e, wrong RF params).
#   Result: country 99, no 5 GHz band, bad RX/TX calibration -> sees few
#   SSIDs and association fails. Removing the empty .txt (v1 of this
#   script) didn't help because "no file" == "built-in generic NVRAM".
#
# Fix: supply a real NVRAM file.
#   A (default) NVRAM captured from Apple's Boot Camp driver on a
#               MacBookPro14,3 (bugzilla 193121 attachment 290569),
#               boardflags3=0x00000303 (comment 81: both bands).
#   B           same, boardflags3=0x00000003 (use if A breaks 2.4 GHz).
#   C           DW1820A-derived NVRAM (attachment 285753), boardflags3
#               0x00000300, ccode=0 regrev=1.
#
# T1 chip: not involved. Wi-Fi is a plain PCIe device; T1 only runs the
#   Touch Bar / Touch ID / camera.
#
# Safety: touches ONLY brcmfmac. The USB adapter (rtw88_8821cu) and all
#         docker/calico bridges are never referenced. Fully reversible;
#         see UNDO at the bottom.
#
# Usage:  sudo ./fix-wifi.sh [--variant A|B|C] [--txcap]   then REBOOT
#         ./fix-wifi.sh --check                             (no root needed)
#   --txcap  cap wlp3s0 txpower at 10 dBm (persistent, via NM dispatcher);
#            fixes "sees network but won't associate" on 2.4 GHz.
#   --check  report bands / MAC / scans after the reboot.
#
# No driver hot-reload: on this Mac, unloading brcmfmac drops the chip
# into D3cold and it can't wake again ("MMIO read failed") until reboot.
# =====================================================================
set -u

SRC="$(cd "$(dirname "$0")" && pwd)/fix-wifi-nvram"
DIR=/usr/lib/firmware/brcm
F="$DIR/brcmfmac43602-pcie.txt"
FB="$DIR/brcmfmac43602-pcie.Apple Inc.-MacBookPro14,3.txt"
DISP=/etc/NetworkManager/dispatcher.d/99-brcm43602-txpower
IFACE=wlp3s0
PHY=phy0
REGDOM=CO          # Colombia, matches the current global regulatory domain
VARIANT=A
TXCAP=0
CHECK=0
MARK="# installed by fix-wifi.sh"

die()  { echo "ERROR: $*" >&2; exit 1; }
bands(){ iw phy "$PHY" info 2>/dev/null | grep -E '^[[:space:]]+Band [0-9]:' | tr -d '\t'; }
has5g(){ iw phy "$PHY" info 2>/dev/null | grep -qE '^[[:space:]]+Band 2:'; }
setkey(){ sed -i "s/^$1=.*/$1=$2/" "$3"; }
scan() { nmcli -t -f SSID,CHAN,SIGNAL device wifi list ifname "$1" --rescan yes 2>/dev/null \
           | awk -F: '$1!=""{printf "    %-28s ch%-4s %s%%\n",$1,$2,$3}' | sort -u; }

while [ $# -gt 0 ]; do
    case "$1" in
        --variant) VARIANT="${2:-}"; shift 2 ;;
        --txcap)   TXCAP=1; shift ;;
        --check)   CHECK=1; shift ;;
        *) die "unknown argument: $1" ;;
    esac
done

# --- Status report (used by --check) -----------------------------------------------------------
report() {
echo "=========== STATUS ==========="
echo "NVRAM:      $( [ -s "$F" ] && grep -m1 '^boardflags3=' "$F" || echo 'none')"
echo "bands:      $(bands | paste -sd' ')"
echo "regulatory: $(iw reg get 2>/dev/null | grep -A1 'phy#0' | tail -1 | xargs)"
echo "MAC:        $(cat /sys/class/net/$IFACE/address 2>/dev/null)"
echo "txpower:    $(iw dev $IFACE info 2>/dev/null | awk '/txpower/{print $2,$3}')"
echo "kernel:"; journalctl -k -b --no-pager 2>/dev/null | grep -i brcmfmac | tail -6 | sed 's/^/    /'
if has5g; then
    echo "5 GHz channels enabled:"
    iw phy "$PHY" info 2>/dev/null \
        | awk '/MHz \[/ && $2+0>=5000 && !/disabled/ {gsub(/[][]/,"",$4); printf "%s ",$4}' \
        | sed 's/^/    /'; echo
fi
echo
echo "Networks seen by internal $IFACE:"
scan "$IFACE"
USB=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: '$2=="wifi" && $1 ~ /^wlx/{print $1; exit}')
if [ -n "$USB" ]; then
    echo "Networks seen by USB $USB (for comparison):"
    scan "$USB"
fi
echo

if [ ! -e "/sys/class/net/$IFACE" ]; then
    echo ">>> $IFACE is missing (chip asleep/failed to probe). Do a full shutdown,"
    echo ">>> wait 10 s, power on, then: ./fix-wifi.sh --check"
elif has5g; then
    echo ">>> SUCCESS: 2.4 + 5 GHz bands available on $IFACE (variant $VARIANT)."
    echo ">>> Connect, then test:"
    echo "      nmcli device wifi connect HiBreak ifname $IFACE"
    echo "      ping -I $IFACE -c 20 8.8.8.8"
    echo ">>> If 2.4 GHz networks vanish/fail: sudo $0 --variant B, then reboot"
    echo ">>> If networks show but won't connect: re-run with --txcap, then reboot"
else
    echo ">>> STILL 2.4 GHz ONLY with NVRAM $(grep -m1 '^boardflags3=' "$F" 2>/dev/null)"
    echo ">>> Try: sudo $0 --variant C   then reboot"
fi
}

if [ "$CHECK" -eq 1 ]; then report; exit 0; fi
[ "$(id -u)" -eq 0 ] || die "must run as root:  sudo $0"
case "$VARIANT" in
    A|B) NV="$SRC/bcm43602-mbp143-bootcamp.txt" ;;
    C)   NV="$SRC/bcm43602-dw1820a.txt" ;;
    *)   die "--variant must be A, B or C" ;;
esac
[ -s "$NV" ] || die "missing NVRAM source $NV"

echo "=========== BEFORE ==========="
echo "bands:      $(bands | paste -sd' ')"
echo "regulatory: $(iw reg get 2>/dev/null | grep -A1 'phy#0' | tail -1 | xargs)"
echo "MAC:        $(cat /sys/class/net/$IFACE/address 2>/dev/null)"
echo

# --- Step 1: build the NVRAM for this variant --------------------------
# Stable, locally administered MAC (the real Apple MAC isn't readable from
# the chip; the firmware default 00:90:4c:0d:f4:3e is shared by every unit).
MAC=$(printf '%s-wlp3s0' "$(cat /etc/machine-id)" | sha256sum \
      | sed -E 's/^(..)(..)(..)(..)(..).*/02:\1:\2:\3:\4:\5/')
TMP=$(mktemp) || die "mktemp failed"
{ echo "$MARK, variant $VARIANT"; tr -d '\r' < "$NV"; } > "$TMP"
setkey macaddr "$MAC" "$TMP"
case "$VARIANT" in
    A) setkey boardflags3 0x00000303 "$TMP" ;;
    B) setkey boardflags3 0x00000003 "$TMP" ;;
    C) setkey boardflags3 0x00000300 "$TMP"
       setkey ccode 0 "$TMP"
       setkey regrev 1 "$TMP" ;;
esac
echo "[1] variant $VARIANT: $(basename "$NV")"
grep -E '^(macaddr|ccode|regrev|boardflags3)=' "$TMP" | sed 's/^/    /'

# --- Step 2: install (back up anything already there, once) ------------
for dst in "$F" "$FB"; do
    # back up only a file we didn't write ourselves
    if [ -e "$dst" ] && ! head -1 "$dst" | grep -qF "$MARK" && [ ! -e "$dst.orig.bak" ]; then
        cp -v "$dst" "$dst.orig.bak"
    fi
    install -m 0644 "$TMP" "$dst" || die "could not write $dst"
done
rm -f "$TMP"
echo "[2] NVRAM installed to $DIR"

# --- Step 3: optional txpower cap --------------------------------------
if [ "$TXCAP" -eq 1 ]; then
    cat > "$DISP" <<'EOF'
#!/bin/sh
# Cap BCM43602 txpower at 10 dBm; the stock 31 dBm breaks association.
[ "$1" = "wlp3s0" ] || exit 0
case "$2" in up|pre-up|connectivity-change) iw dev wlp3s0 set txpower fixed 1000 ;; esac
EOF
    chmod 0755 "$DISP"
    echo "[3] txpower cap installed: $DISP"
else
    echo "[3] no txpower cap (add --txcap if networks are seen but won't connect)"
fi

# --- Step 4: apply at next boot (see header: no hot-reload) ------------
echo "[4] done. NVRAM loads at next boot. Now run:"
echo "      sudo reboot"
echo "    then, after logging in:"
echo "      $0 --check"
echo "    (if $IFACE is missing after reboot, do a full shutdown + power on)"

cat <<UNDO

--------------------------------------------------------------------
UNDO (back to stock = no NVRAM file):
  sudo rm -f "$F" "$FB" "$DISP"
  sudo reboot
  (pre-existing files, if any, were saved as *.orig.bak)
--------------------------------------------------------------------
UNDO
