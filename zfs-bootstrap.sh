#!/bin/bash
# zfs-bootstrap.sh

set -ex

# Update apt and install required packages
UBUNTU_FRONTEND=noninteractive sudo apt-add-repository universe
UBUNTU_FRONTEND=noninteractive sudo apt-get update
UBUNTU_FRONTEND=noninteractive sudo apt-get install -y \
	zfsutils-linux \
	zfs-initramfs \
	debootstrap \
	gdisk \
  dosfstools

# Partition the new root EBS volume
sudo sgdisk -Zg -n1:0:4095 -t1:EF02 -c1:GRUB -n2:0:0 -t2:BF01 -c2:ZFS /dev/sda
zpool destroy -f rpool
sudo mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {}
# Create zpool and filesystems on the new EBS volume
sudo zpool create \
	-o altroot=/mnt \
	-o ashift=12 \
	-o cachefile=/etc/zfs/zpool.cache \
	-O canmount=off \
	-O compression=lz4 \
	-O atime=off \
	-O normalization=formD \
	-m none \
	rpool \
	/dev/sda2

# Root file system
sudo zfs create \
	-o canmount=off \
	-o mountpoint=none \
	rpool/ROOT

sudo zfs create \
	-o canmount=noauto \
	-o mountpoint=/ \
	rpool/ROOT/ubuntu

sudo zfs mount rpool/ROOT/ubuntu

# /home
sudo zfs create \
	-o setuid=off \
	-o mountpoint=/home \
	rpool/home

sudo zfs create \
	-o mountpoint=/root \
	rpool/home/root

# /var
sudo zfs create \
	-o setuid=off \
	-o overlay=on \
	-o mountpoint=/var \
	rpool/var

sudo zfs create \
	-o com.sun:auto-snapshot=false \
	-o mountpoint=/var/cache \
	rpool/var/cache

sudo zfs create \
	-o com.sun:auto-snapshot=false \
	-o mountpoint=/var/tmp \
	rpool/var/tmp

sudo zfs create \
	-o mountpoint=/var/spool \
	rpool/var/spool

sudo zfs create \
	-o exec=on \
	-o mountpoint=/var/lib \
	rpool/var/lib

sudo zfs create \
	-o mountpoint=/var/log \
	rpool/var/log

# Display ZFS output for debugging purposes
sudo zpool status
sudo zfs list

# Bootstrap Ubuntu xenial into /mnt
sudo debootstrap --arch amd64 xenial /mnt

sudo cat > /mnt/etc/apt/sources.list << EOF
deb http://archive.ubuntu.com/ubuntu xenial main universe
deb-src http://archive.ubuntu.com/ubuntu xenial main universe

deb http://security.ubuntu.com/ubuntu xenial-security main universe
deb-src http://security.ubuntu.com/ubuntu xenial-security main universe

deb http://archive.ubuntu.com/ubuntu xenial-updates main universe
deb-src http://archive.ubuntu.com/ubuntu xenial-updates main universe
EOF

# Copy the zpool cache
sudo mkdir -p /mnt/etc/zfs
sudo cp -p /etc/zfs/zpool.cache /mnt/etc/zfs/zpool.cache

# Create mount points and mount the filesystem
sudo mkdir -p /mnt/{dev,proc,sys}
sudo mount --rbind /dev /mnt/dev
sudo mount --rbind /proc /mnt/proc
sudo mount --rbind /sys /mnt/sys

# Copy the bootstrap script into place and execute inside chroot
sudo cp chroot-bootstrap.sh /mnt/tmp/chroot-bootstrap.sh
# sudo chroot /mnt /tmp/chroot-bootstrap.sh
# sudo rm -f /mnt/tmp/chroot-bootstrap.sh

# Remove temporary sources list - CloudInit regenerates it
# sudo rm -f /mnt/etc/apt/sources.list

# This could perhaps be replaced (more reliably) with an `lsof | grep -v /mnt` loop,
# however in approximately 20 runs, the bind mounts have not failed to unmount.
# sleep 10 

# Unmount bind mounts
# sudo umount -l /mnt/dev#sudo umount -l /mnt/proc#sudo umount -l /mnt/sys
# sudo mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {}

# Export the zpool
# sudo zpool export rpool

# Adduser if necessary
# Necessary reboot
# reboot
