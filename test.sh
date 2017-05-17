#!/bin/bash
# test.sh
# Install neccessary packages:
sudo apt-add-repository universe
sudo apt update
sudo apt install zfsutils-linux zfs-initramfs cryptsetup debootstrap dosfstools gdisk mdadm mc nano -y
