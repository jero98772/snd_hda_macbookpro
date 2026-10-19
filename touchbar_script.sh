#!/bin/bash
# Touch Bar / keyboard setup for MacBookPro14,3 (A1707, T1 iBridge 05ac:8600)
# Tested on kernel 6.17. Rerun after a kernel update to rebuild the modules.
set -e

KVER=$(uname -r)

# Dependencies
sudo apt-get update
sudo apt-get install -y git make gcc build-essential wget linux-headers-$KVER

# Audio (cirrus driver from this repo)
cd /tmp && rm -rf snd_hda_macbookpro
git clone https://github.com/davidjo/snd_hda_macbookpro.git
cd snd_hda_macbookpro && sudo ./install.cirrus.driver.sh

# Build and install the iBridge / Touch Bar drivers
cd /tmp && rm -rf macbook12-spi-driver
git clone https://github.com/roadrunner2/macbook12-spi-driver.git
cd macbook12-spi-driver
sudo make clean
sudo make
sudo make install
sudo depmod -a

# Load modules at boot
sudo tee /etc/modules-load.d/touchbar.conf > /dev/null << 'EOF'
intel_lpss_pci
spi_pxa2xx_platform
applespi
apple_ib_tb
apple_ib_als
EOF

# Module options: F-keys by default, hold Fn for media keys
sudo tee /etc/modprobe.d/touchbar.conf > /dev/null << 'EOF'
options applespi fnremap=0
options apple_ib_tb fnmode=2 idle_timeout=60
EOF

# IMPORTANT: hid-sensor-hub grabs the iBridge's second HID interface (the
# Touch Bar display/mode interface) before apple-ibridge can, so the bar
# never turns on. apple_ib_als handles the light sensor without it.
sudo tee /etc/modprobe.d/touchbar-no-sensorhub.conf > /dev/null << 'EOF'
blacklist hid_sensor_hub
install hid_sensor_hub /bin/false
blacklist hid_sensor_als
EOF

# Reset the iBridge once after boot so the drivers attach to it
sudo tee /etc/systemd/system/touchbar-fix.service > /dev/null << 'EOF'
[Unit]
Description=MacBook Touchbar Fix
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/bin/bash -c 'echo 1-3 > /sys/bus/usb/drivers/usb/unbind || true'
ExecStart=/bin/sleep 2
ExecStart=/bin/bash -c 'echo 1-3 > /sys/bus/usb/drivers/usb/bind || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Remove reset services from earlier attempts; they race with touchbar-fix
for svc in macbook-touchbar touchbar-usb-fix; do
    sudo systemctl disable "$svc.service" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/$svc.service"
done
sudo rm -f /etc/modules-load.d/applespi.conf /etc/modprobe.d/applespi.conf /etc/modprobe.d/apple_ib_tb.conf

# Wifi firmware config
sudo wget -O /lib/firmware/brcm/brcmfmac43602-pcie.txt "https://raw.githubusercontent.com/AdnanHodzic/auto-cpufreq/master/auto_cpufreq/data/brcmfmac43602-pcie.Apple%20Inc.-MacBookPro13%2C3.txt"

# Suspend fix
sudo tee /etc/systemd/system/macbook-suspend.service > /dev/null << 'EOF'
[Unit]
Description=Fix MacBook suspend
Before=display-manager.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=/bin/sh -c "echo 0 > /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed"
ExecStart=/bin/sh -c "echo 0 > /sys/bus/pci/devices/0000:04:00.0/d3cold_allowed"
RemainAfterExit=yes
TimeoutSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable touchbar-fix.service macbook-suspend.service
sudo update-initramfs -u -k $KVER

echo "Done. Reboot with: sudo reboot"
