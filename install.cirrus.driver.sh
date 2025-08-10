#!/bin/bash

# NOTA BENE - this script should be run as root

set -e

while [ $# -gt 0 ]
do
    case $1 in
    -i|--install) dkms_action='install';;
    -k|--kernel) UNAME=$2; [[ -z $UNAME ]] && echo '-k|--kernel must be followed by a kernel version' && exit 1;;
    -r|--remove) dkms_action='remove';;
    -u|--uninstall) dkms_action='remove';;
    (-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
    (*) break;;
    esac
    shift
done

UNAME=${1:-$(uname -r)}
kernel_version=$(echo $UNAME | cut -d '-' -f1)  #ie 6.16.0
major_version=$(echo $kernel_version | cut -d '.' -f1)
minor_version=$(echo $kernel_version | cut -d '.' -f2)
major_minor=${major_version}${minor_version}

revision=$(echo $UNAME | cut -d '.' -f3)
revpart1=$(echo $revision | cut -d '-' -f1)
revpart2=$(echo $revision | cut -d '-' -f2)
revpart3=$(echo $revision | cut -d '-' -f3)

if [ $major_version -eq 5 -a $minor_version -lt 13 ]; then
    sed -i 's/^BUILT_MODULE_NAME\[0\].*$/BUILT_MODULE_NAME[0]="snd-hda-codec-cirrus"/' dkms.conf
    PATCH_CIRRUS=true
else
    sed -i 's/^BUILT_MODULE_NAME\[0\].*$/BUILT_MODULE_NAME[0]="snd-hda-codec-cs8409"/' dkms.conf
    PATCH_CIRRUS=false
fi

if [[ $dkms_action == 'install' ]]; then
    bash dkms.sh
    # note that Ubuntu, Debian, Fedora and others (see dkms man page) install to updates/dkms
    # and ignore DEST_MODULE_LOCATION
    # we DO want updates so that the original module is not overwritten
    # (although the original module should be copied to under /var/lib/dkms if needed for other distributions)
    update_dir="/lib/modules/${UNAME}/updates"
    echo -e "\ncontents of $update_dir/dkms"
    ls -lA $update_dir/dkms
    exit
elif [[ $dkms_action == 'remove' ]]; then
    bash dkms.sh -r
    exit
fi

if [ $major_version == '4' ]; then
	echo "Kernel 4 versions no longer supported"
	exit 1
fi

if [ $major_version -eq 5 -a $minor_version -lt 8 ]; then
	echo "Kernel 5 versions less than 5.8 no longer supported"
	exit 1
fi

isdebian=0
isfedora=0
isarch=0
isvoid=0

if [ -d /usr/src/linux-headers-${UNAME} ]; then
	# Debian Based Distro
	isdebian=1
	:
elif [ -d /usr/src/kernels/${UNAME} ]; then
	# Fedora Based Distro
	isfedora=1
	:
elif [ -d /usr/lib/modules/${UNAME} ]; then
	# Arch Based Distro
	isarch=1
	:
elif [ -d /usr/src/kernel-headers-${UNAME} ]; then
	# Void Linux
	isvoid=1
	:
else
	echo "linux kernel headers not found:"
	echo "Debian (eg Ubuntu): /usr/src/linux-headers-${UNAME}"
	echo "Fedora: /usr/src/kernels/${UNAME}"
	echo "Arch: /usr/lib/modules/${UNAME}"
	echo "Void: /usr/src/kernel-headers-${UNAME}"
	echo "assuming the linux kernel headers package is not installed"
	echo "please install the appropriate linux kernel headers package:"
	echo "Debian/Ubuntu: sudo apt install linux-headers-${UNAME}"
	echo "Fedora: sudo dnf install kernel-headers"
	echo "Arch (also Manjaro): Linux: sudo pacman -S linux-headers"
	echo "Void Linux: xbps-install -S linux-headers"

	exit 1
fi

# note that the update_dir definition below relies on a symbolic link of /lib to /usr/lib on Arch
cur_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
build_dir='build'
patch_dir="$cur_dir/patch_cirrus"
hda_dir="$cur_dir/$build_dir/hda"
update_dir="/lib/modules/${UNAME}/updates"

[[ -d $hda_dir ]] && rm -rf $hda_dir
[[ ! -d $build_dir ]] && mkdir $build_dir

# fedora doesnt seem to install patch by default so need to explicitly install it
if [ $isfedora -ge 1 ]; then
	echo "Ensure the patch package is installed"
	[[ ! $(command -v patch) ]] && dnf install -y patch
fi

# Check if this is a T2 kernel (MacBook kernel) or other custom kernel
ist2kernel=0
if [[ $UNAME == *"t2"* ]]; then
    ist2kernel=1
    echo "Detected T2 kernel (MacBook kernel): $UNAME"
fi

# we need to handle Ubuntu based distributions eg Mint here
isubuntu=0
if [ $(grep '^NAME=' /etc/os-release | grep -c Ubuntu) -eq 1 ]; then
	isubuntu=1
fi
if [ $(grep '^NAME=' /etc/os-release | grep -c "Linux Mint") -eq 1 ]; then
	isubuntu=1
fi

# For T2 kernels or other custom kernels, skip the Ubuntu source package logic
if [ $isubuntu -ge 1 ] && [ $ist2kernel -eq 0 ]; then

	# NOTE for Ubuntu we need to use the distribution kernel sources as they seem
	# to be significantly modified from the mainline kernel sources generally with backports from later kernels
	# (so far the actual debian kernels seem to be close to mainline kernels)

	# NOTA BENE this will likely NOT work for Ubuntu hwe kernels which are even more highly
        #           modified with extensive backports from later kernel versions
        #           (and in any case there is no linux-source-... package for hwe kernels)

	if [ ! -e /usr/src/linux-source-$kernel_version.tar.bz2 ]; then

		echo "Ubuntu linux kernel source not found in /usr/src: /usr/src/linux-source-$kernel_version.tar.bz2"
		echo "assuming the linux kernel source package is not installed"
		echo "please install the linux kernel source package:"
		echo "sudo apt install linux-source-$kernel_version"
		echo "NOTE - This does not work for HWE kernels or custom kernels like T2"
		echo "For T2 kernels, the script will use mainline kernel sources instead"

		# For T2 kernels, fall through to mainline kernel download
		if [ $ist2kernel -eq 0 ]; then
			exit 1
		fi
	else
		# Ubuntu source package found, use it
		tar --strip-components=3 -xvf /usr/src/linux-source-$kernel_version.tar.bz2 --directory=build/ linux-source-$kernel_version/sound/pci/hda
		ubuntu_source_used=1
	fi
fi

# If we didn't use Ubuntu sources (T2 kernel, other distros, or Ubuntu source not found)
if [[ ! ${ubuntu_source_used:-0} -eq 1 ]]; then
	# here we assume we need to download mainline kernel source
	echo "Using mainline kernel sources for kernel $kernel_version"

	set +e

	# For newer kernels (6.x), we may need to try different approaches
	if [ $major_version -ge 6 ]; then
		echo "Kernel 6.x detected - using best-match mainline kernel source"
		
		# Try exact version first
		wget -c https://cdn.kernel.org/pub/linux/kernel/v$major_version.x/linux-$kernel_version.tar.xz -P $build_dir
		
		if [[ $? -ne 0 ]]; then
			echo "Failed to download linux-$kernel_version.tar.xz"
			
			# Try without patch version (e.g., 6.16.0 -> 6.16)
			base_version="$major_version.$minor_version"
			echo "Trying base version linux-$base_version.tar.xz"
			kernel_version=$base_version
			wget -c https://cdn.kernel.org/pub/linux/kernel/v$major_version.x/linux-$kernel_version.tar.xz -P $build_dir
			
			if [[ $? -ne 0 ]]; then
				# Try latest stable in the major version
				echo "Trying to find latest available kernel in v$major_version.x series"
				latest_kernel=$(curl -s https://cdn.kernel.org/pub/linux/kernel/v$major_version.x/ | grep -oP 'linux-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=\.tar\.xz)' | sort -V | tail -1)
				if [ ! -z "$latest_kernel" ]; then
					echo "Using latest available kernel: linux-$latest_kernel.tar.xz"
					kernel_version=$latest_kernel
					wget -c https://cdn.kernel.org/pub/linux/kernel/v$major_version.x/linux-$kernel_version.tar.xz -P $build_dir
				fi
				
				[[ $? -ne 0 ]] && echo "Could not download any suitable kernel source...exiting" && exit 1
			fi
		fi
	else
		# Original logic for older kernels
		# attempt to download linux-x.x.x.tar.xz kernel
		wget -c https://cdn.kernel.org/pub/linux/kernel/v$major_version.x/linux-$kernel_version.tar.xz -P $build_dir

		if [[ $? -ne 0 ]]; then
			echo "Failed to download linux-$kernel_version.tar.xz"
			echo "Trying to download base kernel version linux-$major_version.$minor_version.tar.xz"
			echo "This may lead to build failures as too old"
			echo "If this is an Ubuntu-based distribution this almost certainly will fail to build"
			echo ""
			# if first attempt fails, attempt to download linux-x.x.tar.xz kernel
			kernel_version=$major_version.$minor_version
			wget -c https://cdn.kernel.org/pub/linux/kernel/v$major_version.x/linux-$kernel_version.tar.xz -P $build_dir

			[[ $? -ne 0 ]] && echo "kernel could not be downloaded...exiting" && exit
		fi
	fi

	set -e

	tar --strip-components=3 -xvf $build_dir/linux-$kernel_version.tar.xz --directory=build/ linux-$kernel_version/sound/pci/hda
fi

mv $hda_dir/Makefile $hda_dir/Makefile.orig
cp $patch_dir/Makefile $patch_dir/patch_cirrus_* $hda_dir
pushd $hda_dir > /dev/null

# Updated version definitions for newer kernels
current_major=6
current_minor=16
current_minor_ubuntu=15
current_rev_ubuntu=47
latest_rev_ubuntu=71

iscurrent=0
if [ $isubuntu -ge 1 ] && [ $ist2kernel -eq 0 ]; then
	if [ $major_version -gt $current_major ]; then
		iscurrent=2
	elif [ $major_version -eq $current_major -a $minor_version -gt $current_minor_ubuntu ]; then
		iscurrent=2
	elif [ $major_version -eq $current_major -a $minor_version -eq $current_minor_ubuntu -a $revpart2 -gt $latest_rev_ubuntu ]; then
		iscurrent=2
	elif [ $major_version -eq $current_major -a $minor_version -eq $current_minor_ubuntu -a $revpart2 -gt $current_rev_ubuntu ]; then
		iscurrent=1
	elif [ $major_version -eq $current_major -a $minor_version -eq $current_minor_ubuntu -a $revpart2 -eq $current_rev_ubuntu ]; then
		iscurrent=1
	else
		iscurrent=-1
	fi
else
	# For non-Ubuntu or T2 kernels, use more permissive logic
	if [ $major_version -gt $current_major ]; then
		iscurrent=1  # Assume current for newer major versions
	elif [ $major_version -eq $current_major -a $minor_version -gt $current_minor ]; then
		iscurrent=1  # Assume current for newer minor versions
	elif [ $major_version -eq $current_major -a $minor_version -eq $current_minor ]; then
		iscurrent=1
	else
		iscurrent=0  # Older versions but still try to build
	fi
fi

if [ $iscurrent -gt 1 ]; then
	echo "Kernel version later than implemented version - there may be build problems"
fi

if [ $major_version -eq 5 -a $minor_version -lt 13 ]; then
	patch -b -p2 <../../patch_patch_cirrus.c.diff
else
	if [ $isubuntu -ge 1 ] && [ $ist2kernel -eq 0 ]; then

		patch -b -p2 <../../patch_patch_cs8409.c.diff

		if [ $iscurrent -ge 0 ]; then
			patch -b -p2 <../../patch_patch_cs8409.h.diff
		else
			patch -b -p2 <../../patches/patch_patch_cs8409.h.ubuntu.pre51547.diff
		fi

		if [ $iscurrent -ge 0 ]; then
			patch -b -p2 <../../patch_patch_cirrus_apple.h.diff
		fi

	else
		# For T2 kernels and other non-Ubuntu distributions
		patch -b -p2 <../../patch_patch_cs8409.c.diff

		if [ $iscurrent -ge 0 ]; then
			patch -b -p2 <../../patch_patch_cs8409.h.diff
		else
			patch -b -p2 <../../patches/patch_patch_cs8409.h.main.pre519.diff
		fi

		cp $patch_dir/Makefile $patch_dir/patch_cirrus_* $hda_dir/

		if [ $iscurrent -ge 0 ]; then
			patch -b -p2 <../../patch_patch_cirrus_apple.h.diff
		fi
	fi
fi

popd > /dev/null

[[ ! $dkms_action == 'install' ]] && [[ ! -d $update_dir ]] && mkdir $update_dir

if [ $PATCH_CIRRUS = true ]; then
	make PATCH_CIRRUS=1
	make install PATCH_CIRRUS=1
else
	make KERNELRELEASE=$UNAME
	make install KERNELRELEASE=$UNAME
fi

echo -e "\ncontents of $update_dir"
ls -lA $update_dir
