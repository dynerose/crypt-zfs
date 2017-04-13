#!/bin/bash
# chroot-bootstrap.sh
set -ex

# Necessary need universe source
UBUNTU_FRONTEND=noninteractive sudo apt-add-repository universe -y
# Update APT with new sources
UBUNTU_FRONTEND=noninteractive sudo apt-get update  -y

# Do not configure grub during package install
echo 'grub-pc grub-pc/install_devices_empty select true' | debconf-set-selections
echo 'grub-pc grub-pc/install_devices select' | debconf-set-selections

# Install various packages needed for a booting system
UBUNTU_FRONTEND=noninteractive apt-get install -y \
	linux-image-generic \
	linux-headers-generic \
	grub-pc \
	zfsutils-linux \
	zfs-initramfs \
	dosfstools \
	gdisk

# Set the locale to en_US.UTF-8
locale-gen --purge "en_US.UTF-8"
echo -e 'LANG="en_US.UTF-8"\nLANGUAGE="en_US:en"\n' > /etc/default/locale
# dpkg-reconfigure tzdata

# Install OpenSSH
apt-get install -y --no-install-recommends openssh-server

# Install GRUB
# shellcheck disable=SC2016
sed -ri 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="boot=zfs \$bootfs"/' /etc/default/grub
grub-probe /

# Install the boot loader
grub-install /dev/sda

# Configure and update GRUB
# Refresh the initrd files:
update-initramfs -c -k all

mkdir -p /etc/default/grub.d
{
	echo 'GRUB_RECORDFAIL_TIMEOUT=0'
	echo 'GRUB_TIMEOUT=0'
	echo 'GRUB_CMDLINE_LINUX_DEFAULT="console=tty1 console=ttyS0 ip=dhcp tsc=reliable net.ifnames=0"'
	echo 'GRUB_TERMINAL=console'
} > /etc/default/grub.d/50-aws-settings.cfg
update-grub

# Set options for the default interface
{
	echo 'auto ens33'
	echo 'iface ens33 inet dhcp'
} >> /etc/network/interfaces

# Install standard packages
DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-standard cloud-init

ls /boot/grub/*/zfs.mod

# Snapshot the initial installation:
zfs snapshot rpool/ROOT/ubuntu@install
# In the future, you will likely want to take snapshots before each upgrade, 
# and remove old snapshots (including this one) at some point to save space.
