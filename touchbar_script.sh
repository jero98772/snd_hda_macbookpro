sudo apt-get update && sudo apt-get install -y wget make gcc linux-headers-$(uname -r)
cd /tmp && git clone https://github.com/davidjo/snd_hda_macbookpro.git
cd snd_hda_macbookpro && sudo ./install.cirrus.driver.sh
sudo apt-get install -y git dkms
echo -e "\n# macbook12-spi-drivers\napplespi\napple_ib_tb\nspi_pxa2xx_platform\nintel_lpss_pci" | sudo tee -a /etc/initramfs-tools/modules
cd /tmp && git clone https://github.com/roadrunner2/macbook12-spi-driver.git
cd macbook12-spi-driver && git checkout touchbar-driver-hid-driver
sudo dkms add . && sudo dkms install -m applespi -v 0.1 -k $(uname -r)
echo 'options apple_ib_tb fnmode=2' | sudo tee /etc/modprobe.d/apple_ib_tb.conf
echo 'options apple_ib_tb idle_timeout=60' | sudo tee -a /etc/modprobe.d/apple_ib_tb.conf
sudo update-initramfs -u -k $(uname -r)
sudo tee /etc/systemd/system/macbook-touchbar.service > /dev/null << 'EOF'
[Unit]
Description=Re-enable MacBook TouchBar
Before=display-manager.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=/bin/sh -c "echo '1-3' > /sys/bus/usb/drivers/usb/unbind"
ExecStart=/bin/sh -c "echo '1-3' > /sys/bus/usb/drivers/usb/bind"
RemainAfterExit=yes
TimeoutSec=0

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable macbook-touchbar.service
sudo wget -O /lib/firmware/brcm/brcmfmac43602-pcie.txt https://raw.githubusercontent.com/AdnanHodzic/auto-cpufreq/master/auto_cpufreq/data/brcmfmac43602-pcie.Apple%20Inc.-MacBookPro13%2C3.txt
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
sudo systemctl enable macbook-suspend.service
echo "=== CHECKING TOUCHBAR STATUS ==="
echo ""
echo "1. Checking if modules are loaded:"
lsmod | grep -E "applespi|apple_ib_tb|spi_pxa2xx|intel_lpss"
echo ""
echo "2. Checking USB devices (looking for iBridge):"
lsusb | grep -i apple
echo ""
echo "3. Checking dmesg for errors:"
dmesg | grep -i "applespi\|touchbar\|apple_ib" | tail -20
echo ""
echo "4. Checking if modules exist:"
find /lib/modules/$(uname -r) -name "*applespi*" -o -name "*apple_ib*"
echo ""
echo "5. Kernel version:"
uname -r
# Clean up previous attempts
sudo dkms remove applespi/0.1 --all 2>/dev/null || true
sudo rm -rf /usr/src/applespi-0.1
sudo apt-get install -y git dkms build-essential linux-headers-$(uname -r)

# Clone Heratiki's branch (this is the one that actually works)
cd /tmp
rm -rf macbook12-spi-driver
git clone https://github.com/Heratiki/macbook12-spi-driver.git
cd macbook12-spi-driver

# Build it
sudo make clean
sudo make

# Install the modules
sudo make install

# Copy .ko files to the right location
sudo mkdir -p /lib/modules/$(uname -r)/updates/dkms/
sudo cp applespi.ko /lib/modules/$(uname -r)/updates/dkms/ 2>/dev/null || true
sudo cp apple-ib-tb.ko /lib/modules/$(uname -r)/updates/dkms/ 2>/dev/null || true
sudo cp apple-ibridge.ko /lib/modules/$(uname -r)/updates/dkms/ 2>/dev/null || true

# Update dependencies
sudo depmod -a

# Load modules now (test)
sudo modprobe intel_lpss_pci
sudo modprobe spi_pxa2xx_platform
sudo modprobe applespi
sudo modprobe apple_ib_tb

# Check if loaded
lsmod | grep applespi
# Add modules to load at boot
sudo tee /etc/modules-load.d/applespi.conf << 'EOF'
intel_lpss_pci
spi_pxa2xx_platform
applespi
apple_ib_tb
EOF

# Configure module options
sudo tee /etc/modprobe.d/applespi.conf << 'EOF'
options applespi fnremap=0
options apple_ib_tb fnmode=2
options apple_ib_tb idle_timeout=60
EOF

# Update initramfs
sudo update-initramfs -u -k all
# This is ESSENTIAL - touchbar needs USB reset after boot
sudo tee /etc/systemd/system/touchbar-fix.service << 'EOF'
[Unit]
Description=MacBook Touchbar USB Fix
After=multi-user.target
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/bin/bash -c 'echo "1-3" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null || true'
ExecStart=/bin/sleep 2
ExecStart=/bin/bash -c 'echo "1-3" > /sys/bus/usb/drivers/usb/bind 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable touchbar-fix.service
sudo systemctl start touchbar-fix.service
# First, check what kernel version you have
uname -r

# Load modules manually
sudo modprobe intel_lpss_pci
sudo modprobe spi_pxa2xx_platform
sudo modprobe applespi
sudo modprobe apple_ib_tb

# Check if loaded
lsmod | grep -E "applespi|apple_ib"

# Try the USB unbind/bind trick RIGHT NOW
echo "1-3" | sudo tee /sys/bus/usb/drivers/usb/unbind
sleep 2
echo "1-3" | sudo tee /sys/bus/usb/drivers/usb/bind

# Check if touchbar appears
dmesg | tail -30
# Some kernels need specific branches
cd /tmp
rm -rf macbook12-spi-driver
git clone https://github.com/roadrunner2/macbook12-spi-driver.git
cd macbook12-spi-driver

# Check your kernel version
KERNEL_VERSION=$(uname -r | cut -d. -f1,2)
echo "Kernel version: $KERNEL_VERSION"

# If kernel is 5.9+, use this branch
if [[ $(echo "$KERNEL_VERSION >= 5.9" | bc) -eq 1 ]]; then
    echo "Using PatrickVerner fork for kernel 5.9+"
    cd /tmp
    rm -rf macbook12-spi-driver
    git clone https://github.com/PatrickVerner/macbook12-spi-driver.git
    cd macbook12-spi-driver
fi

# Build and install
sudo make clean
sudo make
sudo make install
sudo depmod -a
#!/bin/bash
# COMPLETE TOUCHBAR FIX

# Clean up
sudo dkms remove applespi/0.1 --all 2>/dev/null || true
sudo rm -rf /usr/src/applespi-0.1
sudo apt-get install -y git dkms build-essential linux-headers-$(uname -r)

# Clone and build
cd /tmp
rm -rf macbook12-spi-driver
git clone https://github.com/Heratiki/macbook12-spi-driver.git
cd macbook12-spi-driver
sudo make clean && sudo make && sudo make install

# Setup modules
sudo mkdir -p /lib/modules/$(uname -r)/updates/dkms/
sudo cp *.ko /lib/modules/$(uname -r)/updates/dkms/ 2>/dev/null || true
sudo depmod -a

# Auto-load modules
sudo tee /etc/modules-load.d/applespi.conf << EOF
intel_lpss_pci
spi_pxa2xx_platform
applespi
apple_ib_tb
EOF

# Module options
sudo tee /etc/modprobe.d/applespi.conf << EOF
options applespi fnremap=0
options apple_ib_tb fnmode=2
EOF

# USB fix service
sudo tee /etc/systemd/system/touchbar-fix.service << EOF
[Unit]
Description=MacBook Touchbar Fix
After=multi-user.target

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

sudo systemctl daemon-reload
sudo systemctl enable touchbar-fix.service
sudo update-initramfs -u -k all

echo "DONE! Now run: sudo reboot"
# Manual fix (run after each boot if needed)
echo "1-3" | sudo tee /sys/bus/usb/drivers/usb/unbind
sleep 2
echo "1-3" | sudo tee /sys/bus/usb/drivers/usb/bind
# First, let's see if the apple_ib_tb module exists
find /lib/modules/$(uname -r) -name "*apple*ib*"

# Try to load it manually
sudo modprobe apple_ib_tb

# If that fails, check what error you get
sudo dmesg | tail -20

# Also check module info
modinfo apple_ib_tb 2>/dev/null || echo "Module not found!"
# Your kernel is too new for the old drivers!
# You need PatrickVerner's fork or linux-on-mbp version

# Remove old stuff
sudo dkms remove applespi/0.1 --all 2>/dev/null || true
sudo modprobe -r applespi 2>/dev/null || true
sudo modprobe -r apple_ib_tb 2>/dev/null || true

# Install dependencies
sudo apt-get install -y git dkms build-essential linux-headers-$(uname -r)

# Get the driver that works with newer kernels
cd /tmp
rm -rf macbook12-spi-driver
git clone https://github.com/PatrickVerner/macbook12-spi-driver.git
cd macbook12-spi-driver

# Build it
sudo make clean
sudo make

# Install it
sudo make install

# Update module dependencies
sudo depmod -a

# NOW load the modules
sudo modprobe intel_lpss_pci
sudo modprobe spi_pxa2xx_platform
sudo modprobe applespi
sudo modprobe apple_ib_tb

# Check if loaded
lsmod | grep apple

# Do the USB unbind/bind trick
echo "1-3" | sudo tee /sys/bus/usb/drivers/usb/unbind
sleep 2
echo "1-3" | sudo tee /sys/bus/usb/drivers/usb/bind

# Check dmesg
sudo dmesg | tail -30
cd /tmp
rm -rf linux-mbp-arch
git clone https://github.com/aunali1/linux-mbp-arch.git
cd linux-mbp-arch

# Install the appletb module (this is for newer kernels)
cd appletb-dkms
sudo make dkms-install

# Load it
sudo modprobe apple-ib-tb

# Check
lsmod | grep apple

# USB trick
echo "1-3" | sudo tee /sys/bus/usb/drivers/usb/unbind
sleep 2  
echo "1-3" | sudo tee /sys/bus/usb/drivers/usb/bind
cd /tmp
rm -rf macbook12-spi-driver
git clone https://github.com/roadrunner2/macbook12-spi-driver.git
cd macbook12-spi-driver

# Build
sudo make clean
sudo make
sudo make install
sudo depmod -a

# Load modules
sudo modprobe applespi
sudo modprobe apple-ib-tb

# USB reset
echo "1-3" | sudo tee /sys/bus/usb/drivers/usb/unbind
sleep 2
echo "1-3" | sudo tee /sys/bus/usb/drivers/usb/bind
# Check loaded modules
lsmod | grep apple

# Check USB devices again
lsusb -v -d 05ac:8600 2>/dev/null | grep -A 5 "iProduct"

# Try pressing Esc key on touchbar - does it work?
# Add to modules load
sudo tee /etc/modules-load.d/touchbar.conf << EOF
intel_lpss_pci
spi_pxa2xx_platform
applespi
apple-ib-tb
EOF

# Create service
sudo tee /etc/systemd/system/touchbar-usb-fix.service << EOF
[Unit]
Description=Touchbar USB Reset
After=systemd-modules-load.service
After=multi-user.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/bin/bash -c 'echo 1-3 > /sys/bus/usb/drivers/usb/unbind'
ExecStart=/bin/sleep 2
ExecStart=/bin/bash -c 'echo 1-3 > /sys/bus/usb/drivers/usb/bind'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable touchbar-usb-fix.service

# Update initramfs
sudo update-initramfs -u -k all