#!/bin/bash
# https://pastebin.com/fa83QrBk 
# ZFS-setup.sh      2017-04-20 10:04        http://pastebin.com/fa83QrBk
 
# Auto-installer for clean new system using root on zfs, and optionally on
# luks encrypted disks.  It installs Ubuntu 14.04.04 or 16.04 or Elementary OS
# (based on 16.04) or Linux Mint 18.1 Serena (also based on 16.04) with everything
# needed to support ZFS and potentially LUKS.  Without LUKS everything lives
# in the main ${POOLNAME} pool.  With LUKS then /boot lives in its own boot pool.
# Grub2 is installed to all disks, so the system can boot cleanly from *any*
# disk, even with a failed disk.  User home dirs are in isolated datasets sitting
# in a dedicated HOME dataset.  This means that new user creation is a little more
# than just a "useradd ..." command
#
#   zfs create -o mountpoint=/home/NewUser tank/HOME/NewUser
#   useradd -c "User name" --create-home --home-dir /home/NewUser --user-group NewUser
#   rsync -av /etc/skel/ /home/NewUser
#   chown -R NewUser.NewUser /home/NewUser
 
# This script is meant to be run from an Ubuntu live-CD or a minimal
# install (from a usb key for example).  It will create a list of all disks it
# can see then ask the user to edit that list if required.  All disks listed
# in the created ZFS-setup.disks.txt file will be wiped CLEAN for the install.
 
#############################################################################
# Be aware that plymouth has a weirdness about it.  After booting and seeing
# the cool solar graphical boot splash, you may appear to be left with a
# stuck system.  It's not stuck - just use alt-F2 to switch to tty2 and
# alt-F1 to switch back to tty1.  For some reason it doesn't clear
# the screen properly after boot.
#############################################################################
 
# This script can copy the /etc/ssh directory from the build-host into the newly
# created system.  Makes for *much* easier testing when running multiple times,
# since you have the same host key.  It gets old editing your known_hosts file ...
 
# Basic use from ubuntu-16.04-desktop-amd64.iso Live-CD
#
# Boot ISO, select "Try Ubuntu"
# Open terminal
# sudo -i
# (create a ZFS-Custom.sh file containing any custom stuff you want installed/configured)
# wget http://pastebin.com/raw/fa83QrBk -O ZFS-setup.sh
# chmod +x ZFS-setup.sh ZFS-Custom.sh
# nano ZFS-setup.sh
# (if you use vi or vim you *may* have to do :1,$s/^M// to remove ctrl-M at end of each line)
# (where ^M means ctrl-V followed by <return/enter>)
#    set variables in ZFS-setup.sh - see below for the full list with explanations
# ./ZFS-setup.sh
#    ctrl-C to exit at list of disks
# nano ZFS-setup.disks.txt
#    Ensure list of disks is correct
# ./ZFS-setup.sh
#    press <enter> to accept list of disks and swap size
#    enter password for main userid
#    enter password again
#    press <enter> to accept final disk layout
 
# It will create a few scripts - seen as the "cat > /path/script.sh << EOF" below.
 
# Setup.sh                 : Goes in /root of the new system, and is used to build/install
#                          : the rest of the system after debootstrap.
# Reboot-testing.sh        : Goes in the local build-host /root, and is used for
#                          : entering/exiting the new system via chroot for debugging.
# Replace-failed-drive.sh  : Goes in /root of new system, used to replace a failed drive.
#                          : NOTE - this is incomplete
 
# The following stock files are modified
#
# /usr/share/initramfs-tools/scripts/local-top/cryptroot            (if using LUKS)
# /etc/default/grub
# /etc/default/locale
# /etc/crypttab                                                     (if using LUKS)
# /etc/modules
# /etc/timezone
# /etc/localtime
# /etc/hostname
# /etc/hosts
# /etc/fstab
# /etc/bash.bashrc
# /etc/skel/.bashrc
# /etc/network/interfaces
# /etc/apt/sources.list
# /etc/mdadm/mdadm.conf                                             (if using LUKS)
# /etc/initramfs-tools/initramfs.conf                               (if using LUKS)
# /etc/initramfs-tools/conf.d/resume
 
# The following new files are created
#
# /root/.ssh/authorized_keys
# /etc/udev/rules.d/99-local-crypt.rules                            (if using LUKS)
# /etc/udev/rules.d/61-zfs-vdev.rules
# /etc/apt/apt.conf.d/03proxy                                       (if proxy is defined)
# /etc/apt/apt.conf.d/02periodic
# /etc/sudoers.d/zfsALLOW
# /etc/initramfs-tools/modules
# /etc/initramfs-tools/scripts/luks/get.root_crypt.decrypt_derived  (if using LUKS)
# /etc/initramfs-tools/conf.d/dropbear_network                      (if using LUKS)
# /etc/initramfs-tools/hooks/clean_cryptroot                        (if using LUKS)
# /etc/initramfs-tools/hooks/copy_cryptheaders                      (if using LUKS)
# /etc/initramfs-tools/hooks/mount_cryptroot                        (if using LUKS)
# /etc/initramfs-tools/hooks/busybox2                               (if using LUKS)
# /etc/initramfs-tools/hooks/dropbear.fixup2                        (if using LUKS)
# /etc/initramfs-tools/root/.ssh/authorized_keys                    (if using LUKS)
# /usr/share/initramfs-tools/conf-hooks.d/forcecryptsetup           (if using LUKS)
# /etc/initramfs-tools/scripts/init-premount/zzmdraidforce          (if using LUKS)
# /etc/initramfs-tools/scripts/init-premount/network-down
 
# FIXMEs
#
# - 16.04/xenial now uses new systemd device naming, so eth0 becomes enp0s3 or similar.
#   So /etc/initramfs-tools/scripts/init-premount/network-down must be customized, or we
#   must put "net.ifnames=0 biosdevname=0" on the grub cmdline to use old eth0 style network
#   names rather than the newer enp3s0 type.  Search below for GRUB_CMDLINE_LINUX_DEFAULT
# or
#   https://www.freedesktop.org/wiki/Software/systemd/PredictableNetworkInterfaceNames/
#   https://askubuntu.com/questions/628217/use-of-predictable-network-interface-names-with-alternate-kernels
#   ln -s /dev/null /mnt/etc/udev/rules.d/80-net-setup-link.rules
#   ln -s /dev/null /mnt/etc/udev/rules.d/75-persistent-net-generator.rules
 
# General Notes
#
# If you're backing this system up to a remote backup server (called backup.local) you can set up
# a nice systemd env to handle using mbuffer and zfs to receive the backup streams on the backup box.
#
# Choose a port (13371) to have it listen on and a pool to receive to (backup1)
# Send stream with : zfs send -Rv pool/dataset@snapshot | mbuffer -s 256k -m 500m -O backup.local:13371
# Start/stop and final size/speed msgs go into syslog
#
# /etc/systemd/system/zfs.backup1.service
#
# [Unit]
# Description=Start mbuffer to zfs recv for backup1 pool
# Requires=zfs-mount.service
#
# [Service]
# Type=simple
# ExecStart=/bin/sh -c "/usr/bin/mbuffer -v 2 -q -s 256k -m 500m -I 13371 | /sbin/zfs recv -Fdvu backup1"
# Restart=always
#
# [Install]
# WantedBy=multi-user.target
 
 
# -------Set the following variables -----------------------------------------------------------
 
# Which version of Ubuntu to install trusty=14.04 xenial=16.04 zesty=17.04
SUITE=zesty
 
# Are we installing from ElementaryOS ?  Set to version to install
# ELEMENTARY=loki
 
# Are we installing from Mint Cinnamon ?
# CINNAMON=serena
 
# Base set of packages to install after deboostrap
# Very annoying - can't use { } as in linux-{image,headers}-generic - expansion of variable fails in apt-get in Setup.sh,
# around line 1203 in this script.  So have to use individual packages names, linux-header-generic linux-image-generic and so on
# whois needed for mkpasswd
BASE_PACKAGES="openssh-server openssh-blacklist openssh-blacklist-extra whois rsync mdadm gdisk parted linux-headers-generic linux-image-generic debian-keyring ntp vim-nox openssl openssl-blacklist htop mlocate bootlogd apt-transport-https friendly-recovery irqbalance manpages uuid-runtime apparmor grub-pc-bin acpi-support acpi grub-efi-amd64 efibootmgr xauth memtest86+ avahi-daemon intel-microcode amd64-microcode"
 
# Userid, full name and password to create in new system. If UPASSWORD is blank, will prompt for password
USERNAME=sa
UCOMMENT='Main User'
UPASSWORD=sa
 
# SSH pubkey to add to new system
SSHPUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC3uB7roSJ3EYs9hBAQiUZ9Of53Lm3+JZ6ZVokZnp3CRoRfuVT3zND7DAQYSCo+0MZaaydGB1JrWQfgLImWouiC4bsZEzNhnX6uYQ8qSL8zxsK7xOfeVocP+FHdkKcB85giQFp/onuNwHBWLXw9iC2Z/rrbjN2dPSaDKFWQT7ukE2vqt9TQ6mMpYFBCiHpJUfSxXjgjL7Y1MN58QCJ+PesQEY8hh1DzRBwgY0lY9LYAdrqWwj6AIPPawZTcJnNAwz9wO3a8hAS6i9dK+zHDtSIlArevmP8mpcqhpHEtKZ4TbAel7YRtbvY+w7pENbXQiiNMRkdZ28m6FJAFlIHv/wMpUhgZG3SyfFTDg33VhVFlS0qzvIYjTxMPjGLT4oBXK3+CSBuZKwE3xG39S/oTu++feTCtSu5VZZm9rkzrE77tIoWfGi0eGbfJURP9F9q96F0YuNUAS+gnCw5LzR48sMjqXcUpNHVRwi8XE7TDgl7Fk4JHfJelL3LBjFsZC7uaLmy8I1tk+87xTFd0VyG0cAaX/jMbWn1XGVo1V1uXFYRVmfyiPcJBhUaPQ6z1QDXQzsQLed9nQL9qFFPyjoL0zN7Fp+AVka0kPNhkEl0HIL8KqU7cuoypSeA7EO8Qxk7ay8nSP1PLlYzVUZEvEleBjPHTzO6YZxNMRLZSljp8BoY+lw== Johnny Bravo"
 
# Github SSH pubkey(s) to add
GITPUBKEYS=nukien
# GITPUBKEYS="nukien george harry"
 
# Custom script to run after Setup.sh has run in the debootstrap system.  This is to further install any
# other packages you want, or perform any other setup you need.  It can be simply the name of a bash
# script that you have ready in the same dir as this ZFS-setup.sh script, or it can be a URL, in which case
# it will be fetched and copied into the new system alongside Setup.sh, and executed from within Setup.sh
# NOTE: It will be renamed to "Setup-Custom.sh" in the new system
CUSTOMSCRIPT=ZFS-Custom.sh
# CUSTOMSCRIPT="http://pastebin.com/raw/faX12Y34Z"
 
# System name (also used for mdadm raid set names and filesystem LABELs)
# Note: Only first 10 chars of name will be used for LABELs and the pool name
SYSNAME=zfs
 
# zpool pool name - usually taken from the system name above. Can be overridden here
POOLNAME=rpool
 
# Using LUKS for encryption (y/n) ? Please use a nice long complicated passphrase ...
# If enabled, will encrypt partition_swap (md raid) and partition_data (zfs)
# If PASSPHRASE is blank, will prompt for a passphrase
LUKS=y
PASSPHRASE=sa
# Use detached headers ?  If y then save LUKS headers in /root/headers
# NOTE: not working yet - have to figure out /etc/crypttab and /etc/initramfs-tools/conf.d/cryptroot
DETACHEDHEADERS=
 
# Randomize or zero out the disks for LUKS ?  (y/n)
# Randomizing makes for much better encryption
# Zeroing is good for prepping to create an OVA file, makes for better compression
# NOTE: Can only choose one, not both !
RANDOMIZE=
ZERO=
 
# Using a proxy like apt-cacher-ng ?
PROXY=http://192.168.2.104:3142/
# PROXY=
 
# zpool raid level to use for more than 2 disks - raidz, raidz2, raidz3, mirror
# For 2 disks, will be forced to mirror
ZPOOLEVEL=raidz
 
###################################################
# Specify the host key for the new root-on-zfs system ?
# Can be the RSA or ECDSA key from /etc/ssh
# Leave blank for no specific key - ie: use whatever is generated by the openssh installation
# Be sure to use SINGLE quotes for private key
HOST_ECDSA_KEY='-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIO+XmG1AGCiQUejcjS/aVMGaocBe7TCsEmLctyNoJWFqoAoGCCqGSM49
AwEHoUQDQgAEMG1kiuILJZsxJCi1j5xOrA2CpNETWQ5rA94tgjsX6aqpI8re1pwa
/rnYIYrCL/JafwsmlqKG/HfrkvgozqVn/A==
-----END EC PRIVATE KEY-----'
# Be sure to use DOUBLE quotes for public key
HOST_ECDSA_KEY_PUB="ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBDBtZIriCyWbMSQotY+cTqwNgqTRE1kOawPeLYI7F+mqqSPK3tacGv652CGKwi/yWn8LJpaihvx365L4KM6lZ/w= root@installerbox"
# Be sure to use SINGLE quotes for private key
HOST_RSA_KEY='-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEAzCR0pGQ2ITL2KSgzeASWCGgP+mNQRv+Z7VlOCyjmVctODDl3
SiMHdsLRyhcP1M9jfTBEncKrt4AQIt1f1bjAG4kNEgh18dMUYWtIIZ3HlGP+Ieux
EixkakZ2o1qnhmfPG7W3pnw6UHwwZw3Qg6H760PWAmU12gG3YOEuq9DKmBdw2i80
jqcGGREj+BIdROuPKdH+n3DGE0phQ+NwQzMU77czPh1XwcLBGGpEvvk1zbavyqv5
dunsz3msMuJZH2oBE2PeWr8E2x+nNQ2XZIZdHJD8WJMiPBvHUBYMo7CSEAzwdWcs
g8f4umes/LKakv9/h4e47dOOzU1xFwCNo9lOnQIDAQABAoIBAQCPL8Lgy6lr/+LJ
W3k+ZXkWzGboqWBVbFL7N/iVu0pUQxWrXWNejNNfaabcqPBhxFV0Kbb3MORhAWJQ
EhZ2Qe/9YFPaojSYOgXBjw45BgJHAxvtjvPUW27TXDk6uwtmKsoKFZuLGveMHI+W
uQnYSnX4vswNQhBTqYCGY2vo97oikoyTLGEPURbyNpc1NOI7TGuOXHmOAEhw7WN8
jd1wTm2TEjdqMO6Zk03VJn9h5yu6sR7siqEkzIF5p/sfOXoA2Iwh3Sazrsv63R2p
XBYhnfnrM3UuEd4cKGJjXrv1gxNu1AKGKdq34izjKw/YKJhGRuiLh+9gdMva2TcV
dqOqfYQBAoGBAPm2ocF2Hn10Ud/UkcqQc2uPV7+bHhNALzHG5YeXH9vHJq/rm9D8
UFt3OBneaZMXCWRSl1dTlidmt+yl2wk0JyWFmEHZK2wDu+qcRPKT6y4Du+7QRBQY
IwrBHWi8reCbM/wL+s8cEGFt19ip6jw1K1JIxkTtC2vtG0ayPATJJyexAoGBANFI
IAEnZuf3zqECjdNfSr8ITMIfLZhDs/oPBzWUkwMm9jaIi+cf96hSlLFhMWANZOM6
i2x/68AHT9hINqo25cJeQB0UqLeHaU2JDAKn3LOLtCu7D0bpZKbAVFVgd3XsYrRJ
z5+Zz80WyXa+pHTqnrhTP0xkvCCmbWjz+Q5T9jytAoGBAKAOzvmpE3wITd5xaw1y
r3iXBYCcFZfzQQzf1wmk9Vey+/oww8wdnggyj3QNWpBcaLm0MqtXuVwB/AwkdxQc
KKdlTSWP5MQ0VIPZrFvsMgdpf1FgjvJuUi+3fnk+zxizgougxh9wdpNsi7ilmK0E
y4LPgL53TiXccepLnirXIFDRAoGAXLzaOcitCCO+c4i/Migq5iYWZXsNaEiwCyH3
rt2Mm7v7JMUzQZLf2r3lWAjaqVamGy8JM2YoIKrczdmKJ7k17QB45qoN7W3a0tnk
8ZRS71j72NkGdwTbbi0R8ddSeHXsczm2AGJXO+laEv19wLVq6gExrneBCfLVzsk1
1wyLs+0CgYEAuux1i+/7TMh1LyaiNbqQt4uzlDR+EWnbOBTtku9cE7u/dHuy1roE
QA4S2UhEX0sXdekqsFsIS/Qo3+H9pLC8mAZ1X0sQl102z2Cks1WVruodf8tF58iu
FCMSOeHX+wYqyZSm1zLDONoneY5B3zu1Grc8dZRJSons3iaXWl7zj3M=
-----END RSA PRIVATE KEY-----'
# Be sure to use DOUBLE quotes for public key
HOST_RSA_KEY_PUB="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDMJHSkZDYhMvYpKDN4BJYIaA/6Y1BG/5ntWU4LKOZVy04MOXdKIwd2wtHKFw/Uz2N9MESdwqu3gBAi3V/VuMAbiQ0SCHXx0xRha0ghnceUY/4h67ESLGRqRnajWqeGZ88btbemfDpQfDBnDdCDofvrQ9YCZTXaAbdg4S6r0MqYF3DaLzSOpwYZESP4Eh1E648p0f6fcMYTSmFD43BDMxTvtzM+HVfBwsEYakS++TXNtq/Kq/l26ezPeawy4lkfagETY95avwTbH6c1DZdkhl0ckPxYkyI8G8dQFgyjsJIQDPB1ZyyDx/i6Z6z8spqS/3+Hh7jt047NTXEXAI2j2U6d root@installerbox"
###################################################
 
# Are we configuring to use UEFI ?
# NOTE: Most information for EFI install comes from here :
#   http://blog.asiantuntijakaveri.fi/2014/12/headless-ubuntu-1404-server-with-full.html
# If it detects /sys/firmware/efi then it forces this to y
# Currently not booting properly under UEFI dangit
UEFI=
 
# Force the swap partition size for each disk in MB if you don't want it calculated
# If you want Resume to work, total swap must be > total ram
# For 2 disks, will use raid-1 striped, so total = size_swap * num_disks
# For 3+ disks, will use raid-10, so total = size_swap * num_disks / 2
# Set to 0 to disable (SIZE_SWAP = swap partitions, SIZE_ZVOL = zfs zvol in ${POOLNAME})
SIZE_SWAP=100
# Use a zfs volume for swap ?  Set the total size of that volume here.
# NOTE: Cannot be used for Resume
SIZE_ZVOL=100
 
# Use zswap compressed page cache in front of swap ? https://wiki.archlinux.org/index.php/Zswap
USE_ZSWAP="\"zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=25\""
# USE_ZSWAP=
 
# Remove systemd ?  If set to y will remove systemd and replace with upstart
##### NOTE : Not working yet
# REMOVE_SYSTEMD=yes
 
# Set the source of debootstrap - can be a local repo built with apt-move or uncommenting the the lines below
# https://wiki.ubuntu.com/SergeHallyn_localrepo
DEBOOTSTRAP="http://us.archive.ubuntu.com/ubuntu/"
# DEBOOTSTRAP="file:///root/UBUNTU"
#-------------------------------------------------
# mkdir -p ${DEBOOTSTRAP}/dists/${SUITE}/main/binary-amd64 ${DEBOOTSTRAP}/pool/main
# apt-get --no-install-recommends install debootstrap apt-utils
# debootstrap --download-only ${SUITE} ${DEBOOTSTRAP}/cache
# mv ${DEBOOTSTRAP}/cache/var/cache/apt/archive/* ${DEBOOTSTRAP}/pool/main
# cd ${DEBOOTSTRAP}
# apt-ftparchive package pool/main | gzip -9c > dists/${SUITE}/main/binary-amd64/Packages.gz
# cat > release.conf << EOF
# APT::FTPArchive::Release {
# Origin "APT-Move";
# Label "APT-Move";
# Suite "${SUITE}";
# Codename "${SUITE}";
# Architectures "amd64";
# Components "main";
# Description "Local Updates";
# };
# EOF
# apt-ftparchive -c release.conf release dists/${SUITE}/ > dists/${SUITE}/Release
#-------------------------------------------------
 
# Generic partition setup as follows
# sdX1 :    EFI boot
# sdX2 :    Grub boot
# sdX3 :    /boot (only used for LUKS)
# sdX4 :    swap
# sdX5 :    main ZFS partition
# sdX9 :    ZFS reserved
 
# Partition numbers and sizes of each partition in MB
PARTITION_EFI=1
PARTITION_GRUB=2
PARTITION_BOOT=3
PARTITION_SWAP=4
PARTITION_DATA=5
PARTITION_RSVD=9

SIZE_EFI=256
SIZE_GRUB=5
SIZE_BOOT=500


 
# ------ End of user settable variables ---------------------------------------------------
 
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi
 
[ -d /sys/firmware/efi ] && UEFI=y
 
# System name for labels, main pool, etc.
BOXNAME=${SYSNAME:0:10}
# Main pool name
[ ! ${POOLNAME} ] && POOLNAME=${SYSNAME:0:10}
if [ ${#SYSNAME} -gt 10 ]; then
    echo "$(tput setaf 1)!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!$(tput sgr0)"
    echo "$(tput setaf 1)!!$(tput sgr0)"
    echo "$(tput setaf 1)!!$(tput setaf 6) ${SYSNAME}$(tput sgr0) is too long - must be 10 chars max"
    echo "$(tput setaf 1)!!$(tput sgr0) Will use $(tput setaf 6)${BOXNAME}$(tput sgr0) in labels and poolname"
    echo "$(tput setaf 1)!!$(tput sgr0)"
    echo "$(tput setaf 1)!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!$(tput sgr0)"
    echo "$(tput setaf 3) Press <enter> to continue, or ctrl-C to abort $(tput setaf 1)"
    read -t 10 QUIT
    echo ""
fi
 
# Generate (if necessary) list of disks and ask user below if it's good to go
# [ ! -e /root/ZFS-setup.disks.txt ] && for disk in $(ls -l /dev/disk/by-id | egrep -v '(CDROM|CDRW|-ROM|CDDVD|-part|md-|dm-|wwn-)' | sort -t '/' -k3 | tr -s " " | cut -d' ' -f9); do echo $disk >> /root/ZFS-setup.disks.txt; done
[ ! -e /root/ZFS-setup.disks.txt ] && for disk in $(fdisk -l 2>/dev/null | egrep -o '(/dev/[^:]*):' |awk -F: '{print $1}'); do echo $disk >> /root/ZFS-setup.disks.txt; done
 
i=1
for disk in $(cat /root/ZFS-setup.disks.txt) ; do
    DISKS[$i]=$disk
    i=$(($i+1))
done
 
# Calculate proper SWAP size (if not defined above) - should be same size as total RAM in system
MEMTOTAL=$(cat /proc/meminfo | fgrep MemTotal | tr -s ' ' | cut -d' ' -f2)
[ ${SIZE_SWAP} ] || SIZE_SWAP=$(( ${MEMTOTAL} / ${#DISKS[@]} / 1024 ))
 
echo -n "$(tput setaf 1)!!!!!!!!!!!!!!!! $(tput setaf 4)Installing $(tput setaf 7)${SUITE} "
[ ${SUITE} = "trusty" ] && echo -n "14.04"
[ ${SUITE} = "xenial" ] && echo -n "16.04"
[ ${SUITE} = "zesty" ] && echo -n "17.04"

if [ "ZZ${LUKS}" = "ZZy" ]; then
    echo -n " $(tput setaf 4)on LUKS "
else
    echo -n "$(tput setaf 1)!!!!!!!!!"
fi
echo "$(tput setaf 1)!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "$(tput setaf 1)!!"
echo "$(tput setaf 1)!!$(tput sgr0)  These are the disks we're about for $(tput setaf 1)FORMAT$(tput sgr0) for ZFS"
echo "$(tput setaf 1)!!"
i=1
for disk in $(seq 1 ${#DISKS[@]}) ; do
    echo "$(tput setaf 1)!!$(tput sgr0)  disk $i = ${DISKS[$i]} ($(readlink ${DISKS[$i]} | cut -d/ -f3))"
    i=$(($i+1))
done
echo "$(tput setaf 1)!!"
echo "$(tput setaf 1)!!$(tput sgr0)  Be $(tput setaf 1)SURE$(tput sgr0), really $(tput setaf 1)SURE$(tput sgr0), as they will be wiped completely"
echo "$(tput setaf 1)!!$(tput sgr0)  Otherwise abort and edit the $(tput setaf 6)/root/ZFS-setup.disks.txt$(tput sgr0) file"
echo "$(tput setaf 1)!!"
 
if [ ${SIZE_SWAP} ] && [ ${SIZE_SWAP} != 0 ]; then
    if [ ${#DISKS[@]} = 1 ]; then
        SIZE_SWAP_TOTAL=${SIZE_SWAP}
    elif [ ${#DISKS[@]} = 2 ]; then
        # raid1 striped size
        SIZE_SWAP_TOTAL=$(( ${SIZE_SWAP} * ${#DISKS[@]} ))
    else # More than 2 disks
        # raid10 size
        SIZE_SWAP_TOTAL=$(( ${SIZE_SWAP} * ${#DISKS[@]} / 2 ))
    fi
    echo "$(tput setaf 1)!!$(tput sgr0)  ${#DISKS[@]} SWAP partitions of ${SIZE_SWAP}MB = $(( ${SIZE_SWAP_TOTAL} / 1024 ))GB = ${SIZE_SWAP_TOTAL}MB total"
    echo -n "$(tput setaf 1)!!$(tput sgr0)  Ram = ${MEMTOTAL}kb Swap partitions $(tput setaf 3)"
    if [ ${#DISKS[@]} = 1 ]; then
        echo -n ""
    elif [ ${#DISKS[@]} = 2 ]; then
        echo -n "raid1"
    else
        echo -n "raid10"
    fi
    echo " $(tput sgr0)= $(( ${SIZE_SWAP_TOTAL} * 1024 ))kb "
 
    # Say whether resume is possible
    if [ ${MEMTOTAL} -gt $(( ${SIZE_SWAP_TOTAL} * 1024 )) ] ; then
        SWAPRESUME=n
        echo "$(tput setaf 1)!!$(tput sgr0)  Hibernate/Resume $(tput setaf 1)NOT$(tput sgr0) possible"
    else
        SWAPRESUME=y
        echo "$(tput setaf 1)!!$(tput sgr0)  Hibernate/Resume $(tput setaf 6)IS$(tput sgr0) possible"
    fi
   
    echo "$(tput setaf 1)!!$(tput sgr0)  Edit $(tput setaf 6)/root/ZFS-setup.sh$(tput sgr0) to force the swap partition size with SIZE_SWAP"
    echo "$(tput setaf 1)!!$(tput sgr0)  NOTE: If only 2 disks   -> swap partitions are raid1/mirrored."
    echo "$(tput setaf 1)!!$(tput sgr0)        More than 2 disks -> swap partitions are raid10."
    echo "$(tput setaf 1)!!"
fi
 
echo "$(tput setaf 1)!!!!!!!!$(tput setaf 3) Press <enter> to continue, or ctrl-C to abort $(tput setaf 1)!!!!!!!!!!!!!!!!!!!!!$(tput sgr0)"
read -t 10 QUIT
 
# Input USERNAME password for main id
if [ "ZZ${UPASSWORD}" = "ZZ" ] ; then
    DONE=false
    until ${DONE} ; do
        echo ""
        echo "$(tput sgr0)Please enter password for $(tput setaf 3)${USERNAME}$(tput sgr0) in new system"
        read -s -p "Password: " PASSWORD1
        echo ""
        read -s -p "Password again: " PASSWORD2
        [ ${PASSWORD1} = ${PASSWORD2} ] && DONE=true
    done
    echo ""
    UPASSWORD=${PASSWORD1}
fi
 
# Input LUKS encryption passphrase
if [ "ZZ${PASSPHRASE}" = "ZZ" ] && [ "ZZ${LUKS}" = "ZZy" ] ; then
    DONE=false
    until ${DONE} ; do
        echo ""
        echo "$(tput sgr0)Please enter $(tput setaf 3)passphrase$(tput sgr0) for disk encryption for new system"
        read -s -p "Passphrase: " PASSWORD1
        echo ""
        read -s -p "Passphrase again: " PASSWORD2
        [ ${PASSWORD1} = ${PASSWORD2} ] && DONE=true
    done
    echo ""
    PASSPHRASE=${PASSWORD1}
fi
 
# Log everything we do
rm -f /root/ZFS-setup.log
exec > >(tee -a "/root/ZFS-setup.log") 2>&1
 
# Proxy
if [ ${PROXY} ]; then
    # These are for debootstrap
    export http_proxy=${PROXY}
    export ftp_proxy=${PROXY}
    # This is for apt-get
    echo 'Acquire::http::proxy "${PROXY}";' > /etc/apt/apt.conf.d/03proxy
fi
 
# If a CDROM is listed in sources.list it borks things up.  We want latest from internet anyway ...
# ElementaryOS and Linux Mint18 have a cdrom listed for example
sed -i 's/deb cdrom/## deb cdrom/' /etc/apt/sources.list
 
### TODO
# Need to wait till apt update is finished
# Elementary uses packagekitd when booted from dvd/iso
# Elementary uses apt.systemd.daily when booted from minimal install
# - name: Check for apt.systemd.daily
#   shell: ps axf | grep apt.systemd.daily | grep -v grep | cut -c1-5 | tr -d ' '
#   register: apt_systemd_daily
#
# - name: Wait for apt.systemd.daily ({{ apt_systemd_daily.stdout }}) to exit
#   wait_for:
#     path: "/proc/{{ apt_systemd_daily.stdout }}/cmdline"
#     state: absent
#     timeout: 180
#   when: apt_systemd_daily.stdout != ""
 
apt-get -qq update > /dev/null
for UTIL in /sbin/{gdisk,mdadm,cryptsetup} /usr/sbin/debootstrap ; do
    [ ! -e ${UTIL} ] && apt-get -qq -y --no-install-recommends install `basename ${UTIL}`
done
 
echo "-----------------------------------------------------------------------------"
echo "Clearing out md raid and LUKS info from disks"
# Stop all found mdadm arrays
mdadm --stop --force /dev/md* > /dev/null 2>&1
for DISK in `seq 1 ${#DISKS[@]}` ; do
    echo ">>>>> ${DISKS[${DISK}]}"
	
    # Wipe mdadm superblock from all partitions found, even if not md raid partition
    mdadm --zero-superblock --force ${DISKS[${DISK}]} > /dev/null 2>&1
    [ -e ${DISKS[${DISK}]}${PARTITION_BOOT} ] && mdadm --zero-superblock --force ${DISKS[${DISK}]}${PARTITION_BOOT} > /dev/null 2>&1
    [ -e ${DISKS[${DISK}]}${PARTITION_SWAP} ] && mdadm --zero-superblock --force ${DISKS[${DISK}]}${PARTITION_SWAP} > /dev/null 2>&1
    [ -e ${DISKS[${DISK}]}${PARTITION_RSVD} ] && mdadm --zero-superblock --force ${DISKS[${DISK}]}${PARTITION_RSVD} > /dev/null 2>&1
 
    # Clear any old LUKS or mdadm info
    [ -e ${DISKS[${DISK}]}${PARTITION_DATA} ] && dd if=/dev/zero of=${DISKS[${DISK}]}${PARTITION_DATA} bs=512 count=20480 > /dev/null 2>&1
    [ -e ${DISKS[${DISK}]}${PARTITION_SWAP} ] && dd if=/dev/zero of=${DISKS[${DISK}]}${PARTITION_SWAP} bs=512 count=20480 > /dev/null 2>&1
    [ -e ${DISKS[${DISK}]}${PARTITION_RSVD} ] && dd if=/dev/zero of=${DISKS[${DISK}]}${PARTITION_RSVD} bs=512 count=4096 > /dev/null 2>&1
 
    # wipe it out ...
    wipefs -a ${DISKS[${DISK}]}
    # Zero old MBR and GPT partition information on disks
    sgdisk -Z ${DISKS[${DISK}]}
done
 
# Make sure we have utilities we need
if [ ! -e /sbin/zpool ]; then
    if [ "$(lsb_release -cs)" = "trusty" ] ; then
        apt-add-repository --yes ppa:zfs-native/stable
        echo "--- apt-get update"
        apt-get -qq update > /dev/null
        apt-get -qq -y --no-install-recommends install ubuntu-zfs zfsutils
    fi
    # Ubuntu = xenial  ElementaryOS = loki  Mint18 Cinnamon = serena
	
    if [ "$(lsb_release -cs)" = "xenial" ] || [ "$(lsb_release -cs)" = "zesty" ] || [ "$(lsb_release -cs)" = "${ELEMENTARY}" ] || [ "$(lsb_release -cs)" = "${CINNAMON}" ]; then
        sed -i 's/restricted/restricted universe/' /etc/apt/sources.list
        echo "--- apt-get update"
        apt-get -qq update > /dev/null
        apt-get -qq -y --no-install-recommends install zfsutils-linux spl
    fi 
    modprobe zfs
fi
 
# For more packages whose name doesn't match the executable, use this method
#
# UTIL_FILE[0]=/sbin/mdadm ;            UTIL_PKG[0]=mdadm
# UTIL_FILE[1]=/sbin/gdisk ;            UTIL_PKG[1]=gdisk
# UTIL_FILE[3]=/usr/sbin/debootstrap ;  UTIL_PKG[2]=debootstrap
# UTIL_FILE[4]=/usr/sbin/sshd ;         UTIL_PKG[4]=openssh-server
# for UTIL in `seq 0 ${#UTIL_FILE[@]}` ; do
#   UTIL_INSTALL="${UTIL_INSTALL} ${UTIL_PKG[${UTIL}]}"
# done
# apt-get -qq -y --no-install-recommends install ${UTIL_INSTALL}
 
# Unmount any mdadm disks that might have been automounted
umount /dev/md* > /dev/null 2>&1
 
# Stop all found mdadm arrays - again, just in case.  Sheesh.
mdadm --stop --force /dev/md* > /dev/null 2>&1
 
# Randomize or zero entire disk if requested
if [ "ZZ${RANDOMIZE}" = "ZZy" ] || [ "ZZ${ZERO}" = "ZZy" ]; then
    echo "-----------------------------------------------------------------------------"
    if [ "ZZ${RANDOMIZE}" = "ZZy" ] ; then
        echo "Fetching frandom kernel module"
        # urandom is limited, so use frandom module
        [ ! -e /var/lib/dpkg/info/build-essential.list ] && apt-get -qq -y install build-essential
        mkdir -p /usr/src/frandom
        wget --no-proxy http://billauer.co.il/download/frandom-1.1.tar.gz -O /usr/src/frandom/frandom-1.1.tar.gz
        cd /usr/src/frandom
        tar xvzf frandom-1.1.tar.gz
        cd frandom-1.1
        make
        install -m 644 frandom.ko /lib/modules/`uname -r`/kernel/drivers/char/
        depmod -a
        modprobe frandom
        SRC_DEV="/dev/frandom"
    else
        SRC_DEV="/dev/zero"
    fi
 
    for DISK in `seq 1 ${#DISKS[@]}` ; do
        echo "Zeroing/Randomizing ${DISKS[${DISK}]}"
        dd if=${SRC_DEV} of=${DISKS[${DISK}]} bs=512 count=$(blockdev --getsz ${DISKS[${DISK}]}) &
        WAITPIDS="${WAITPIDS} "$!
    done
 
    # USR1 dumps status of dd, this will take around 6 hours for 3TB SATA disk
    # killall -USR1 dd
 
    echo "Waiting for disk zeroing/randomizing to finish"
    wait ${WAITPIDS}
    for DISK in `seq 1 ${#DISKS[@]}` ; do
        partprobe ${DISKS[${DISK}]}
    done
fi
 
echo "-----------------------------------------------------------------------------"
echo "Clearing out zpool info from disks, creating partitions"
for DISK in `seq 1 ${#DISKS[@]}` ; do
    echo ">>>>> ${DISKS[${DISK}]}"
 
    # Clear any old zpool info
    zpool labelclear -f ${DISKS[${DISK}]} > /dev/null 2>&1
    [ -e ${DISKS[${DISK}]}${PARTITION_DATA} ] && zpool labelclear -f ${DISKS[${DISK}]}${PARTITION_DATA} > /dev/null 2>&1
 
    # Create new GPT partition label on disks
    parted -s -a optimal ${DISKS[${DISK}]} mklabel gpt
    # Rescan partitions
    partprobe ${DISKS[${DISK}]}
 
    if [ "ZZ${UEFI}" = "ZZy" ]; then
        sgdisk -n1:2048:+${SIZE_EFI}M -t1:EF00 -c1:"EFI_${DISK}"  ${DISKS[${DISK}]}
    fi
        sgdisk -n2:0:+${SIZE_GRUB}M -t2:EF02 -c2:"GRUB_${DISK}" ${DISKS[${DISK}]}
    if [ "ZZ${LUKS}" = "ZZy" ]; then
        sgdisk -n3:0:+${SIZE_BOOT}M -t3:FD00 -c3:"BOOT_${DISK}" ${DISKS[${DISK}]}
    fi
    if [ ${SIZE_SWAP} ] && [ ${SIZE_SWAP} != 0 ]; then
        sgdisk -n4:0:+${SIZE_SWAP}M -t4:FD00 -c4:"SWAP_${DISK}" ${DISKS[${DISK}]}
    fi
        sgdisk -n5:0:-8M            -t5:BF01 -c5:"ZFS_${DISK}"  ${DISKS[${DISK}]}
        sgdisk -n9:0:0              -t9:BF07 -c9:"RSVD_${DISK}" ${DISKS[${DISK}]}
    partprobe ${DISKS[${DISK}]}
    echo ""
done
echo "---- Sample disk layout -----------------------------------"
gdisk -l ${DISKS[1]}
 
# And, just to be sure, since sometimes stuff hangs around
# Unmount any mdadm disks that might have been automounted
umount /dev/md* > /dev/null 2>&1
 
# Stop all found mdadm arrays
mdadm --stop --force /dev/md* > /dev/null 2>&1
 
# Have to make sure we can actually SEE all the new partitions, so sleep a couple of times
# If you get errors about No such file or directory for ata-xxxxxx this is needed
sleep 5
echo "---- List of disks and -part5 partitions ------------------"
for DISK in `seq 1 ${#DISKS[@]}` ; do
    partprobe ${DISKS[${DISK}]}
    ls -la ${DISKS[${DISK}]}
    ls -la ${DISKS[${DISK}]}${PARTITION_DATA}
done
sleep 5
 
# Build list of partitions to use for ...
# Boot partition (mirror across all disks)
PARTSBOOT=
PARTSSWAP=
PARTSRSVD=
PARTSEFI=
# ZFS partitions to create zpool with
ZPOOLDISK=
for DISK in `seq 1 ${#DISKS[@]}` ; do
    PARTSSWAP="${DISKS[${DISK}]}${PARTITION_SWAP} ${PARTSSWAP}"
    PARTSBOOT="${DISKS[${DISK}]}${PARTITION_BOOT} ${PARTSBOOT}"
    PARTSEFI="${DISKS[${DISK}]}${PARTITION_EFI} ${PARTSEFI}"
    if [ "ZZ${LUKS}" = "ZZy" ]; then
        PARTSRSVD="${DISKS[${DISK}]}${PARTITION_RSVD} ${PARTSRSVD}"
        ZPOOLDISK="/dev/mapper/root_crypt${DISK} ${ZPOOLDISK}"
    else
        ZPOOLDISK="${DISKS[${DISK}]}${PARTITION_DATA} ${ZPOOLDISK}"
    fi
done
 
# Pick raid level to use dependent on number of disks
# disks = 2 : zpool and swap use mirror
# disks > 2 : zpool use raidz, swap use raid10
case ${#DISKS[@]} in
    0)
        echo "**************************************"
        echo "***  Something wrong - no drives defined"
        echo "**************************************"
        exit 1
        ;;
    1)
        ZPOOLEVEL=
        ;;
    2)
        ZPOOLEVEL=mirror
        SWAPRAID=raid1
        ;;
    *)
        # ZPOOLEVEL is left to whatever you chose at top in vars list
        SWAPRAID="raid10 -p f2"
        ;;
esac
 
# Create raid for swap if SIZE_SWAP defined (use -p f2 for raid10)
if [ ${SIZE_SWAP} ] && [ ${SIZE_SWAP} != 0 ]; then
    if [ ${#DISKS[@]} = 1 ]; then
        SWAPDEVRAW=${PARTSSWAP}
    elif [ ${#DISKS[@]} -gt 1 ]; then
        echo "-----------------------------------------------------------------------------"
        echo "Creating ${BOXNAME}:swap ${SWAPRAID} for new system"
        echo y | mdadm --create /dev/md/${BOXNAME}:swap --metadata=1.0 --force --level=${SWAPRAID} --raid-devices=${#DISKS[@]} --homehost=${BOXNAME} --name=swap --assume-clean ${PARTSSWAP}
        SWAPDEVRAW="/dev/md/${BOXNAME}:swap"
    fi
fi
 
# Format EFI System Partitions on all disks as FAT32 in raid1
if [ "ZZ${UEFI}" = "ZZy" ]; then
    echo "-----------------------------------------------------------------------------"
    echo "Creating ${BOXNAME}:efi mirror for new system"
    echo y | mdadm --create /dev/md/${BOXNAME}:efi --metadata=1.0 --force --level=mirror --raid-devices=${#DISKS[@]} --homehost=${BOXNAME} --name=efi --assume-clean ${PARTSEFI}
    mkfs.vfat -v -F32 -s2 -n "${BOXNAME}_efi" /dev/md/${BOXNAME}:efi > /dev/null
 
    #for DISK in `seq 1 ${#DISKS[@]}` ; do
    #   echo "${DISKS[${DISK}]}${PARTITION_EFI}"
    #   mkfs.vfat -v -F32 -s2 -n "EFI_${DISK}" ${DISKS[${DISK}]}${PARTITION_EFI} > /dev/null 2>&1
    #done
fi
 
# Create LUKS devices if LUKS enabled
if [ "ZZ${LUKS}" = "ZZy" ]; then
    echo "-----------------------------------------------------------------------------"
    mkdir -p /root/headers
    # Create encrypted rsvd on top of md array - used as main key for other encrypted
    if [ ${#DISKS[@]} = 1 ]; then
        RSVDDEVRAW=${PARTSRSVD}
    else
        RSVDDEVRAW="/dev/md/${BOXNAME}:rsvd"
        echo "Creating ${BOXNAME}:rsvd raid0 for new system"
        echo y | mdadm --create ${RSVDDEVRAW} --metadata=1.0 --force --level=raid1 --raid-devices=${#DISKS[@]} --homehost=${BOXNAME} --name=rsvd ${PARTSRSVD}
    fi
   
    # If using detached headers
    if [ "ZZ${DETACHEDHEADERS}" = "ZZy" ]; then
        truncate -s 2M /root/headers/LUKS-header-${BOXNAME}:rsvd.luksheader
        LUKSHEADER="--align-payload=0 --header /root/headers/LUKS-header-${BOXNAME}:rsvd.luksheader"
    else
        LUKSHEADER=
    fi
 
    echo "Encrypting ${RSVDDEVRAW}"
    echo ${PASSPHRASE} | cryptsetup --batch-mode luksFormat ${LUKSHEADER} -c aes-xts-plain64 -s 512 -h sha512 ${RSVDDEVRAW}
    echo ${PASSPHRASE} | cryptsetup luksOpen ${LUKSHEADER} ${RSVDDEVRAW} ${BOXNAME}:rsvd
    ln -sf /dev/mapper/${BOXNAME}:rsvd /dev
 
    # Get derived key to insert into other encrypted devices
    # More secure - do this into a small ramdisk
    /lib/cryptsetup/scripts/decrypt_derived ${BOXNAME}:rsvd > /tmp/key
    echo "-----------------------------------------------------------------------------"
 
    # Create encrypted swap on top of md raid array
    if [ ${SIZE_SWAP} ] && [ ${SIZE_SWAP} != 0 ]; then
        echo "Encrypting SWAP ${SWAPDEVRAW}"
 
        # If using detached headers
        if [ "ZZ${DETACHEDHEADERS}" = "ZZy" ]; then
            truncate -s 2M /root/headers/LUKS-header-${BOXNAME}:swap.luksheader
            echo ${PASSPHRASE} | cryptsetup --batch-mode luksFormat -c aes-xts-plain64 -s 512 -h sha512 --align-payload=0 --header /root/headers/LUKS-header-${BOXNAME}:swap.luksheader ${SWAPDEVRAW}
            echo ${PASSPHRASE} | cryptsetup luksOpen --align-payload=0 --header /root/headers/LUKS-header-${BOXNAME}:swap.luksheader ${SWAPDEVRAW} ${BOXNAME}:swap
            echo ${PASSPHRASE} | cryptsetup luksAddKey /root/headers/LUKS-header-${BOXNAME}:swap.luksheader /tmp/key
        else
            # No detached header
            echo ${PASSPHRASE} | cryptsetup --batch-mode luksFormat -c aes-xts-plain64 -s 512 -h sha512 ${SWAPDEVRAW}
            echo ${PASSPHRASE} | cryptsetup luksOpen ${SWAPDEVRAW} ${BOXNAME}:swap
            # Insert derived key
            echo ${PASSPHRASE} | cryptsetup luksAddKey ${SWAPDEVRAW} /tmp/key
        fi
 
        ln -sf /dev/mapper/${BOXNAME}:swap /dev/${BOXNAME}:swap
    fi
 
    # Create encrypted ZFS source partitions
    for DISK in `seq 1 ${#DISKS[@]}` ; do
        echo "Encrypting ZFS partition ${DISKS[${DISK}]}${PARTITION_DATA}"
        # If using detached headers
        if [ "ZZ${DETACHEDHEADERS}" = "ZZy" ]; then
            truncate -s 2M /root/headers/LUKS-header-${DISKS[${DISK}]}${PARTITION_DATA}.luksheader
            echo ${PASSPHRASE} | cryptsetup --batch-mode luksFormat -c aes-xts-plain64 -s 512 -h sha512 --align-payload=0 --header /root/headers/LUKS-header-${DISKS[${DISK}]}${PARTITION_DATA}.luksheader ${DISKS[${DISK}]}${PARTITION_DATA}
            echo ${PASSPHRASE} | cryptsetup luksOpen --align-payload=0 --header /root/headers/LUKS-header-${DISKS[${DISK}]}${PARTITION_DATA}.luksheader ${DISKS[${DISK}]}${PARTITION_DATA} root_crypt${DISK}
            # Insert derived key
            echo ${PASSPHRASE} | cryptsetup luksAddKey /root/headers/LUKS-header-${DISKS[${DISK}]}${PARTITION_DATA}.luksheader /tmp/key
            # Backup LUKS headers for ZFS partitions
            cryptsetup luksHeaderBackup /root/headers/LUKS-header-${DISKS[${DISK}]}${PARTITION_DATA}.luksheader --header-backup-file /root/headers/LUKS-header-backup-${DISKS[${DISK}]}${PARTITION_DATA}.img
        else
            # No detached header
            echo ${PASSPHRASE} | cryptsetup --batch-mode luksFormat -c aes-xts-plain64 -s 512 -h sha512 ${DISKS[${DISK}]}${PARTITION_DATA}
            echo ${PASSPHRASE} | cryptsetup luksOpen ${DISKS[${DISK}]}${PARTITION_DATA} root_crypt${DISK}
            # Insert derived key
            echo ${PASSPHRASE} | cryptsetup luksAddKey ${DISKS[${DISK}]}${PARTITION_DATA} /tmp/key
            # Backup LUKS headers for ZFS partitions
            cryptsetup luksHeaderBackup ${DISKS[${DISK}]}${PARTITION_DATA} --header-backup-file /root/headers/LUKS-header-backup-${DISKS[${DISK}]}${PARTITION_DATA}.img
        fi # Detached headers
 
        # Really, REALLY ugly hack to accomodate update-grub
        ln -sf /dev/mapper/root_crypt${DISK} /dev/root_crypt${DISK}
        ln -sf ${DISKS[${DISK}]}${PARTITION_BOOT} /dev
    done
else # not LUKS
    # Really, REALLY ugly hack to accomodate update-grub
    for DISK in `seq 1 ${#DISKS[@]}` ; do
        # Only create non-mapper DATA partition link if *not* using LUKS
        ln -sf ${DISKS[${DISK}]}${PARTITION_DATA} /dev
    done
fi # LUKS
 
# Now create the ZFS pool(s) - only need the boot pool if using LUKS
echo "-----------------------------------------------------------------------------"
if [ "ZZ${LUKS}" = "ZZy" ]; then
    echo "Creating pool $(tput setaf 1)boot$(tput sgr0) ${ZPOOLEVEL}"
    # Looks like grub boots up fine with all features enabled
    # zpool create -f -o ashift=12 -m none \
    #   -d \
    #   -o feature@async_destroy=enabled \
    #   -o feature@empty_bpobj=enabled \
    #   -o feature@lz4_compress=enabled \
    #   -o feature@spacemap_histogram=enabled \
    #   -o feature@enabled_txg=enabled \
    zpool create -f -o ashift=12 -m none \
        -O atime=off -O canmount=off -O compression=lz4 \
        boot ${ZPOOLEVEL} ${PARTSBOOT}
 
    zfs set com.sun:auto-snapshot=false boot
    zpool export boot
fi # LUKS
 
# Create main zpool - named for 1st 10 chars of system name
echo "Creating main pool $(tput setaf 1)${POOLNAME}$(tput sgr0) ${ZPOOLEVEL}"
# Looks like grub boots up fine with all features enabled
# zpool create -f -o ashift=12 \
#   -d \
#   -o feature@async_destroy=enabled \
#   -o feature@empty_bpobj=enabled \
#   -o feature@lz4_compress=enabled \
#   -o feature@spacemap_histogram=enabled \
#   -o feature@enabled_txg=enabled \
zpool create -f -o ashift=12 \
    -O atime=off -O canmount=off -O compression=lz4 \
    ${POOLNAME} ${ZPOOLEVEL} ${ZPOOLDISK}
zfs set mountpoint=/ ${POOLNAME}
 
# Mount ${POOLNAME} under /mnt/zfs to install system, clean /mnt/zfs first
zpool export ${POOLNAME}
rm -rf /mnt/zfs

if [ "ZZ${LUKS}" = "ZZy" ]; then
    zpool import -d /dev/mapper -R /mnt/zfs ${POOLNAME}
else
    zpool import -d /dev/disk/by-id -R /mnt/zfs ${POOLNAME}
#	${DISKS[${DISK}]}${PARTITION_DATA}
fi
 
# No need to auto-snapshot the pool itself, though you have to explicitly set true for datasets
zfs set com.sun:auto-snapshot=false ${POOLNAME}
# Set threshold for zfs-auto-snapshot so if you *do* enable snapshots, there's a sane default
zfs set com.sun:snapshot-threshold=2000000 ${POOLNAME}
 
# Create container for root dataset
zfs create -o canmount=off -o mountpoint=none -o compression=lz4 -o atime=off ${POOLNAME}/ROOT
 
# Enable auto snapshots with zfs-auto-snapshot
zfs set com.sun:auto-snapshot=true ${POOLNAME}/ROOT
# Set threshold for zfs-auto-snapshot
zfs set com.sun:snapshot-threshold=2000000 ${POOLNAME}/ROOT
 
# Create root dataset to hold main filesystem
zfs create -o canmount=noauto -o mountpoint=/ -o compression=lz4 -o atime=off -o xattr=sa ${POOLNAME}/ROOT/ubuntu
zpool set bootfs=${POOLNAME}/ROOT/ubuntu ${POOLNAME}
zfs mount ${POOLNAME}/ROOT/ubuntu
 
# Create container for HOME datasets
zfs create -o canmount=off -o mountpoint=none -o compression=lz4 -o atime=off ${POOLNAME}/HOME
 
# Enable auto snapshots with zfs-auto-snapshot
zfs set com.sun:auto-snapshot=true ${POOLNAME}/HOME
# Set threshold for zfs-auto-snapshot
zfs set com.sun:snapshot-threshold=2000000 ${POOLNAME}/HOME
 
# Create home dataset for main user
zfs create -o canmount=on -o mountpoint=/home/${USERNAME} -o compression=lz4 -o atime=off -o xattr=sa ${POOLNAME}/HOME/${USERNAME}
zfs mount ${POOLNAME}/HOME/${USERNAME}
 
if [ "ZZ${LUKS}" = "ZZy" ]; then
    zpool import -d /dev/disk/by-id -R /mnt/zfs boot
    # Set up /boot filesystem and possibly for EFI
    # Create dataset to hold boot filesystem
    zfs create -o mountpoint=/boot -o compression=zle -o atime=off -o xattr=sa boot/ubuntu
    # Enable auto snapshots with zfs-auto-snapshot
    zfs set com.sun:auto-snapshot=true boot/ubuntu
    # Set threshold for zfs-auto-snapshot
    zfs set com.sun:snapshot-threshold=2000000 boot/ubuntu
 
    # Copy header backups and detached headers
    mkdir -p /mnt/zfs/root/headers
    cp -a /root/headers /mnt/zfs/root/
fi
 
# Create swap in zfs
if [ ${SIZE_ZVOL} != 0 ]; then
    zfs create -V ${SIZE_ZVOL}M -b $(getconf PAGESIZE) \
              -o compression=zle \
              -o primarycache=metadata \
              -o secondarycache=none \
              -o sync=always \
              -o logbias=throughput \
              -o com.sun:auto-snapshot=false ${POOLNAME}/SWAP
fi
 
# Copy Custom script into debootstrap system.  If it has "http" in the name, fetch it, then copy it
# Script is renamed to Setup-Custom.sh in new system
if [ ! -z ${CUSTOMSCRIPT+x} ] ; then
    echo "Installing $(tput setaf 6)Setup-Custom.sh$(tput sgr0) from ${CUSTOMSCRIPT}"
    mkdir -p /mnt/zfs/root
    if [[ "${CUSTOMSCRIPT}" =~ "http" ]]; then
        wget --no-proxy ${CUSTOMSCRIPT} -O /mnt/zfs/root/Setup-Custom.sh
    else
        if [ -e ${CUSTOMSCRIPT} ]; then
            cp ${CUSTOMSCRIPT} /mnt/zfs/root/Setup-Custom.sh
        else
            echo "$(tput setaf 1)**** NOTE: $(tput setaf 3)${CUSTOMSCRIPT}$(tput setaf 1) does not exist !!$(tput sgr0)"
        fi
    fi
    chmod +x /mnt/zfs/root/Setup-Custom.sh
fi
 
echo "--------------------- $(tput setaf 1)About to debootstrap into /mnt/zfs$(tput sgr0) --------------------"
df -h
echo "--------------------- $(tput setaf 1)About to debootstrap into /mnt/zfs$(tput sgr0) --------------------"
zpool status -v
zfs list -t all
echo "--------------------- $(tput setaf 1)About to debootstrap into /mnt/zfs$(tput sgr0) --------------------"
echo "------- $(tput setaf 1)Please check the above listings to be sure they're right$(tput sgr0) ------------"
echo "------- $(tput setaf 3)Press <enter> About to debootstrap into /mnt/zfs$(tput sgr0) --------------------"
read -t 10 QUIT
 
# Copy existing kernel modules into new system so depmod will work when zfs is installed there
mkdir -p /mnt/zfs/lib/modules
cp -a /lib/modules/* /mnt/zfs/lib/modules
 
# Install core system - need wget to get signing keys in Setup.sh
# See # https://wiki.ubuntu.com/SergeHallyn_localrepo for how to set up a local repository
debootstrap --arch=amd64 --no-check-gpg --include=wget ${SUITE} /mnt/zfs ${DEBOOTSTRAP}
 
# ======== Now create Setup.sh script ====================================================
#   Setup.sh    : To use inside chroot - NOTE this runs when we actually chroot into /mnt/zfs
 
# Locale etc just nasty - trying to get it set up front for when we chroot in to run Setup.sh
cat > /mnt/zfs/root/.bash_aliases << EOF
export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"
export LANGUAGE="en_US"
EOF
 
cat > /mnt/zfs/root/Setup.sh << __EOFSETUP__
#!/bin/bash
export BOXNAME=${BOXNAME}
export SYSNAME=${SYSNAME}
export POOLNAME=${POOLNAME}
export LUKS=${LUKS}
export DETACHEDHEADERS=${DETACHEDHEADERS}
export PASSPHRASE=${PASSPHRASE}
export UEFI=${UEFI}
export PROXY=${PROXY}
export REMOVE_SYSTEMD=${REMOVE_SYSTEMD}
export SUITE=${SUITE}
export BASE_PACKAGES="${BASE_PACKAGES}"
export ELEMENTARY=${ELEMENTARY}
export CINNAMON=${CINNAMON}
export USERNAME=${USERNAME}
export UCOMMENT="${UCOMMENT}"
export UPASSWORD=${UPASSWORD}
export SSHPUBKEY="${SSHPUBKEY}"
export GITPUBKEYS="${GITPUBKEYS}"
export SIZE_SWAP=${SIZE_SWAP}
export SIZE_ZVOL=${SIZE_ZVOL}
export SWAPRESUME=${SWAPRESUME}
export SWAPDEVRAW=${SWAPDEVRAW}
export USE_ZSWAP=${USE_ZSWAP}
export RSVDDEVRAW=${RSVDDEVRAW}
export CUSTOMSCRIPT=${CUSTOMSCRIPT}
export PARTITION_EFI=${PARTITION_EFI}
export PARTITION_GRUB=${PARTITION_GRUB}
export PARTITION_BOOT=${PARTITION_BOOT}
export PARTITION_SWAP=${PARTITION_SWAP}
export PARTITION_DATA=${PARTITION_DATA}
export PARTITION_RSVD=${PARTITION_RSVD}
export HOST_ECDSA_KEY_PUB="${HOST_ECDSA_KEY_PUB}"
export HOST_RSA_KEY_PUB="${HOST_RSA_KEY_PUB}"
__EOFSETUP__
# Ugly hack to get multiline variable into Setup.sh
# Note using single quotes like this  HOST_RSA_KEY='blahblah' surrounded by double quotes
echo -n "HOST_ECDSA_KEY='" >> /mnt/zfs/root/Setup.sh
echo "${HOST_ECDSA_KEY}'" >> /mnt/zfs/root/Setup.sh
echo -n "HOST_RSA_KEY='" >> /mnt/zfs/root/Setup.sh
echo "${HOST_RSA_KEY}'" >> /mnt/zfs/root/Setup.sh
 
for DISK in $(seq 1 ${#DISKS[@]}) ; do
    echo "DISKS[${DISK}]=${DISKS[${DISK}]}" >> /mnt/zfs/root/Setup.sh
done
 
# Note use of ' for this section to avoid replacing $variables - did not use ' above
cat >> /mnt/zfs/root/Setup.sh << '__EOFSETUP__'
 
# Testing functionality of removing systemd completely
# https://askubuntu.com/questions/779640/how-to-remove-systemd-from-ubuntu-16-04-and-prevent-its-usage
Remove_systemd() {
    apt-get install -y upstart-sysv sysvinit-utils
 
    # Set up preferences to pin systemd AWAY
    apt-get remove --purge --auto-remove -y --allow-remove-essential systemd
    echo -e 'Package: systemd\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/systemd
    echo -e '\n\nPackage: *systemd*\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/systemd
    echo -e '\nPackage: systemd:amd64\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/systemd
    echo -e '\nPackage: systemd:i386\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/systemd
}
 
# Stuff to do after a basic debootstrap
set -x
# Log everything we do
exec > >(tee -a /root/Setup.log) 2>&1
 
# Proxy
if [ ${PROXY} ]; then
    # This is for apt-get
    echo "Acquire::http::proxy \"${PROXY}\";" > /etc/apt/apt.conf.d/03proxy
fi
 
# Disable predicatable network interface names - see :
#   https://www.freedesktop.org/wiki/Software/systemd/PredictableNetworkInterfaceNames/
#   https://askubuntu.com/questions/628217/use-of-predictable-network-interface-names-with-alternate-kernels
# Also setting net.ifnames=0 in /etc/default/grub further down
ln -s /dev/null /etc/udev/rules.d/80-net-setup-link.rules
 
# Basic network interfaces
cat >> /etc/network/interfaces << __EOF__
# The loopback network interface
auto lo
iface lo inet loopback
 
# The primary network interface
auto eth0
iface eth0 inet dhcp
__EOF__
 
# Nice clean sources.list, if on Amazon AWS grab local region archive address
# plymouth makes no sense for AWS, never see the console. PLYMOUTH variable
# is used for apt install below.  AWS implies it's a VPS ...
mv /etc/apt/sources.list /etc/apt/sources.list.orig
EC2=$(fgrep ec2 /etc/apt/sources.list.orig | fgrep ${SUITE} | head -1 | sed 's/^.*\/\///; s/ ${SUITE}.*//')
if [ "ZZ${EC2}" = "ZZ" ]; then
    # Not Amazon AWS, so need a source
    EC2=archive.ubuntu.com/ubuntu
    if [ ${SUITE} = trusty ]; then
        PLYMOUTH="plymouth-theme-solar"
    else
        PLYMOUTH="plymouth-theme-ubuntu-logo plymouth-label plymouth-themes"
    fi
else
    # Amazon AWS, so EC2 is already pointing at right local source
    PLYMOUTH=
    VPS=true
fi
cat > /etc/apt/sources.list << EOF
deb http://${EC2} ${SUITE} main restricted universe multiverse
deb http://${EC2} ${SUITE}-updates main restricted universe multiverse
deb http://${EC2} ${SUITE}-backports main restricted universe multiverse
deb http://archive.canonical.com/ubuntu ${SUITE} partner
deb http://security.ubuntu.com/ubuntu ${SUITE}-security main restricted universe multiverse
EOF
if [ ${SUITE} = trusty ]; then
    echo "deb http://extras.ubuntu.com/ubuntu ${SUITE} main" >> /etc/apt/sources.list
fi
 
# Set up for periodic apt updates
cat > /etc/apt/apt.conf.d/02periodic << EOFAPT1
// This enables periodic upgrades of packages - see /etc/cron.daily/apt for details
// NOTE: These default Ubuntu settings are in /etc/apt/apt.conf.d/20auto-upgrades
// APT::Periodic::Unattended-Upgrade "1";
 
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Enable "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOFAPT1
 
# Prevent apt-get from asking silly questions
export DEBIAN_FRONTEND=noninteractive
 
# apt-key adv fails within a debootstrap, so try wget
# apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3E5C1192
# apt-key adv --keyserver keyserver.ubuntu.com --recv-keys CA8DA16B
# apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 437D05B5
# apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C0B21F32
wget --no-proxy "http://keyserver.ubuntu.com:11371/pks/lookup?op=get&search=0x3E5C1192" -O- | apt-key add - > /dev/null 2>&1
wget --no-proxy "http://keyserver.ubuntu.com:11371/pks/lookup?op=get&search=0xCA8DA16B" -O- | apt-key add - > /dev/null 2>&1
wget --no-proxy "http://keyserver.ubuntu.com:11371/pks/lookup?op=get&search=0x437D05B5" -O- | apt-key add - > /dev/null 2>&1
# apt-fast PPA key
wget --no-proxy "http://keyserver.ubuntu.com:11371/pks/lookup?op=get&search=0xC0B21F32" -O- | apt-key add - > /dev/null 2>&1
 
# Ugly hack to prevent launching of services while setting up system with apt-get
##### NOTE : Putting update-initramfs here to prevent it from running a bazillion times during the install
#####          : Will remove it and run update-initramfs manually at the end
mkdir -p /tmp/fakestart
ln -s /bin/true /tmp/fakestart/initctl
ln -s /bin/true /tmp/fakestart/invoke-rc.d
ln -s /bin/true /tmp/fakestart/restart
ln -s /bin/true /tmp/fakestart/start
ln -s /bin/true /tmp/fakestart/stop
ln -s /bin/true /tmp/fakestart/start-stop-daemon
ln -s /bin/true /tmp/fakestart/service
ln -s /bin/true /tmp/fakestart/update-initramfs
export PATH=/tmp/fakestart:$PATH
 
export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"
export LANGUAGE="en_US"
# Set up locale - must set langlocale variable (defaults to en_US)
cat > /tmp/selections << EOFLOCALE
# tzdata
tzdata  tzdata/Zones/US      select Eastern
tzdata  tzdata/Zones/America select New_York
tzdata  tzdata/Areas         select US
# localepurge will not take any action
localepurge     localepurge/remove_no   note
# Inform about new locales?
localepurge     localepurge/dontbothernew       boolean false
localepurge     localepurge/showfreedspace      boolean true
# Really remove all locales?
localepurge     localepurge/none_selected       boolean false
# Default locale for the system environment:
locales locales/default_environment_locale      select en_US.UTF-8
localepurge     localepurge/verbose     boolean false
# Selecting locale files
localepurge     localepurge/nopurge     multiselect en, en_US.UTF-8
localepurge     localepurge/use-dpkg-feature boolean true
locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8
localepurge     localepurge/quickndirtycalc  boolean true
localepurge     localepurge/mandelete   boolean true
EOFLOCALE
 
# if ! [ -e /etc/default/locale ]; then
    cat > /etc/default/locale << EOF
LC_ALL=en_US.UTF-8
LANG=en_US.UTF-8
LANGUAGE=en_US
EOF
# fi
cat /etc/default/locale >> /etc/environment
 
cat /tmp/selections | debconf-set-selections
echo "--- apt-get update"
apt-get -qq update > /dev/null
apt-get -qq -y install localepurge locales language-pack-en-base
locale-gen "en_US.UTF-8"
dpkg-reconfigure -f noninteractive locales
 
# This is a workaround for https://bugs.launchpad.net/ubuntu/+source/tzdata/+bug/1554806
echo "America/New_York" > /etc/timezone
ln -fs /usr/share/zoneinfo/US/Eastern /etc/localtime
dpkg-reconfigure -f noninteractive tzdata
 
echo "${SYSNAME}" > /etc/hostname
echo "127.0.1.1 ${SYSNAME}.local    ${SYSNAME}" >> /etc/hosts
 
# Remove systemd if requested
if [ ! -z ${REMOVE_SYSTEMD} ]; then
    Remove_systemd
fi
 
apt-get -qq -y install ubuntu-minimal software-properties-common
 
if [ ${SUITE} = trusty ]; then
    apt-add-repository --yes ppa:zfs-native/stable
fi
 
# If we're installing ElementaryOS or Linux Mint 18.1, set up the additional PPAs
# Regular Ubuntu uses ubuntu-standard - change below for ElementaryOS or Linux Mint
STANDARD="ubuntu-standard"
 
if [ "${ELEMENTARY}ZZ" != "ZZ" ]; then
    add-apt-repository --yes ppa:elementary-os/stable
    add-apt-repository --yes ppa:elementary-os/os-patches
    # Use elementary-standard rather than ubuntu-standard for ElementaryOS
    STANDARD="elementary-standard"
    cat > /etc/apt/preferences.d/elementary-os-patches.pref << EOF
# Explanation: OS patches for elementary OS.
# Explanation: We need this pin because our patched build can lag a few hours behind Ubuntu's updates,
# Explanation: and during those few hours packages can be overwritten with unpatched ones.
Package: *
Pin: release o=LP-PPA-elementary-os-os-patches
Pin-Priority: 999
EOF
fi # Elementary
 
if [ "${CINNAMON}ZZ" != "ZZ" ]; then
    # Cinnamon uses the stock ubuntu-standard
 
    # Mint PPA key 451BBBF2 or sub is A5D54F76
    # apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 451BBBF2
    wget --no-proxy "http://keyserver.ubuntu.com:11371/pks/lookup?op=get&search=0x451BBBF2" -O- | apt-key add - > /dev/null 2>&1
 
    cat > /etc/apt/preferences.d/cinnamon-extra.pref << EOF
Package: *
Pin: origin build.linuxmint.com
Pin-Priority: 700
EOF
 
    cat > /etc/apt/preferences.d/cinnamon-packages.pref << EOF
Package: *
Pin: origin live.linuxmint.com
Pin-Priority: 750
 
Package: *
Pin: release o=linuxmint,c=upstream
Pin-Priority: 700
 
Package: *
Pin: release o=Ubuntu
Pin-Priority: 500
EOF
 
    cat > /etc/apt/sources.list.d/linux-mint-serena.list<< EOF
deb http://packages.linuxmint.com serena main upstream import backport #id:linuxmint_main
EOF
fi # Cinnamon
 
echo "--- apt-get update"
apt-get -qq update > /dev/null
 
# Force overwrite of config files - needed when installed from 16.04 live disc
# https://askubuntu.com/questions/56761/force-apt-get-to-overwrite-file-installed-by-another-package
# https://askubuntu.com/questions/104899/make-apt-get-or-aptitude-run-with-y-but-not-prompt-for-replacement-of-configu
# STANDARD is set above, choosing between ElementaryOS and Ubuntu version of the -standard package
apt-get -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Options::="--force-overwrite" -y --no-install-recommends install ${BASE_PACKAGES} ${PLYMOUTH} ${STANDARD}
 
# Set host ssh keys if defined
# Test if variable set - https://stackoverflow.com/questions/3601515/how-to-check-if-a-variable-is-set-in-bash
# DOESN'T work if variable is set to null, as in HOST=  that creates the variable, so +x test fails
# if [ ! -z ${HOST_RSA_KEY+x} ] ; then
if [ "${HOST_RSA_KEY}ZZ" != "ZZ" ] ; then
    echo "${HOST_RSA_KEY}" > /etc/ssh/ssh_host_rsa_key
    echo "${HOST_RSA_KEY_PUB}" > /etc/ssh/ssh_host_rsa_key.pub
    chmod 600 /etc/ssh/ssh_host_rsa_key
    chmod 644 /etc/ssh/ssh_host_rsa_key.pub
fi
if [ "${HOST_ECDSA_KEY}ZZ" != "ZZ" ] ; then
    echo "${HOST_ECDSA_KEY}" > /etc/ssh/ssh_host_ecdsa_key
    echo "${HOST_ECDSA_KEY_PUB}" > /etc/ssh/ssh_host_ecdsa_key.pub
    chmod 600 /etc/ssh/ssh_host_ecdsa_key
    chmod 644 /etc/ssh/ssh_host_ecdsa_key.pub
fi
 
# Set up mdadm - clear out any previous array definitions
cat /etc/mdadm/mdadm.conf | fgrep -v ARRAY > /tmp/ttt
mv /tmp/ttt /etc/mdadm/mdadm.conf
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
 
# spl package (from ubuntu-zfs) provides /etc/hostid
rm -f /etc/hostid
if [ ${SUITE} = trusty ]; then
        apt-get -qq -y --no-install-recommends install ubuntu-zfs ubuntu-extras-keyring
fi
if [ ${SUITE} = xenial ]; then
        apt-get -qq -y --no-install-recommends install zfsutils-linux spl zfs-zed
        depmod -a
        modprobe zfs
fi
apt-get -qq -y install zfs-initramfs
 
# Allow read-only zfs commands with no sudo password
cat /etc/sudoers.d/zfs | sed -e 's/#//' > /etc/sudoers.d/zfsALLOW
 
# Create swap
if [ ${SIZE_SWAP} ] && [ ${SIZE_SWAP} != 0 ]; then
    if [ "ZZ${LUKS}" = "ZZy" ]; then
        echo "Create encrypted SWAP ${BOXNAME}_swap on top of ${BOXNAME}:swap"
        mkswap -L "${BOXNAME}_swap" /dev/mapper/${BOXNAME}:swap
        [ ${SWAPRESUME} = y ] && echo "RESUME=/dev/mapper/${BOXNAME}:swap" > /etc/initramfs-tools/conf.d/resume
    else
        mkswap -L "${BOXNAME}_swap" ${SWAPDEVRAW}
        [ ${SWAPRESUME} = y ] && echo "RESUME=${SWAPDEVRAW}" > /etc/initramfs-tools/conf.d/resume
    fi
fi
if [ ${SIZE_ZVOL} != 0 ]; then
    mkswap -L "${BOXNAME}_zwap"  /dev/zvol/${POOLNAME}/SWAP
fi
 
# If using LUKS set up crypttab etc
if [ "ZZ${LUKS}" = "ZZy" ]; then
    apt-get -qq -y install cryptsetup
    if [ "`cat /proc/cpuinfo | fgrep aes`" != "" ] ; then
        echo "aesni-intel" >> /etc/modules
        echo "aesni-intel" >> /etc/initramfs-tools/modules
    fi
    echo "aes-x86_64" >> /etc/modules
    echo "aes-x86_64" >> /etc/initramfs-tools/modules
 
    # Was using dedicated per-luks-device lines for 99-local-crypt.rules
    # But https://github.com/zfsonlinux/zfs/wiki/Ubuntu-16.04-Root-on-ZFS shows a generic way, which I think is better
    #if [ ${SIZE_SWAP} ] && [ ${SIZE_SWAP} != 0 ]; then
    #   echo "ENV{DM_NAME}==\"${BOXNAME}:swap\", SYMLINK+=\"${BOXNAME}:swap\"" > /etc/udev/rules.d/99-local-crypt.rules
    #fi
    #echo "ENV{DM_NAME}==\"${BOXNAME}:rsvd\", SYMLINK+=\"${BOXNAME}:rsvd\"" >> /etc/udev/rules.d/99-local-crypt.rules
    #for DISK in `seq 1 ${#DISKS[@]}` ; do
    #   echo "ENV{DM_NAME}==\"root_crypt${DISK}\", SYMLINK+=\"root_crypt${DISK}\"" >> /etc/udev/rules.d/99-local-crypt.rules
    #done
    cat > /etc/udev/rules.d/99-local-crypt.rules << 'EOF'
# Was using dedicated per-luks-device lines for 99-local-crypt.rules
# But https://github.com/zfsonlinux/zfs/wiki/Ubuntu-16.04-Root-on-ZFS shows a generic way, which I think is better
#
# Old way
#   echo "ENV{DM_NAME}==\"${BOXNAME}:swap\", SYMLINK+=\"${BOXNAME}:swap\"" > /etc/udev/rules.d/99-local-crypt.rules
 
ENV{DM_NAME}!="", SYMLINK+="$env{DM_NAME}"
ENV{DM_NAME}!="", SYMLINK+="dm-name-$env{DM_NAME}"
EOF
 
    # Make decrypt_derived only use the encrypted :rsvd system for pulling the derived key
    mkdir /etc/initramfs-tools/scripts/luks
    cp /lib/cryptsetup/scripts/decrypt_derived /etc/initramfs-tools/scripts/luks/get.root_crypt.decrypt_derived
    cp /lib/cryptsetup/scripts/decrypt_derived /etc/initramfs-tools/scripts/luks/decrypt_derived
    sed -i "
    { 2 a\
        CRYPT_DEVICE=${BOXNAME}:rsvd \\
    }
    { s/\$1/\${CRYPT_DEVICE}/g }
    " /etc/initramfs-tools/scripts/luks/get.root_crypt.decrypt_derived
 
    # Force inclusion of cryptsetup
    echo "export CRYPTSETUP=y" > /usr/share/initramfs-tools/conf-hooks.d/forcecryptsetup
 
    # Reduce cryptroot timeout from 180s to 30s and remove dropping to shell if missing device
    # Also ignore fstype check for ${BOXNAME}:rsvd - ZFS safety partition 9
    # That is used as the source key for unlocking all the other luks devices
    # Include system IP address on boot unlock screen
    sed -i "
       s/slumber=180/slumber=30/g
       s/panic/break # panic/
       /cryptsetup: unknown fstype, bad password or options/ {
       i \
           if [[ ! \"\$crypttarget\" =~ \":rsvd\" ]] ; then
 
       N ; N ; N ; a\
           fi  # check for ZFS
       }
        s/Please unlock disk/For \$eth0IP Please unlock disk/
        /PREREQ=/ {
        a \
# Need to pause here to let network come up\n\
sleep 7\n\
eth0IP=\$(ifconfig eth0 | sed -n '/inet addr/s/.*inet addr: *\([^[:space:]]\+\).*/\1/p')
       
        }
    " /usr/share/initramfs-tools/scripts/local-top/cryptroot
   
    # Help update-initramfs to find all encrypted disks for root - remove "return" from get_root_device()
    sed -i '/echo "$device"/ { N ; s!echo "$device"\n\(.*\)return!echo "$device"\n\1# https://newspaint.wordpress.com/2015/03/22/installing-xubuntu-14-04-trusty-on-zfs-with-luks-encryption/\n\1# return! } ' /usr/share/initramfs-tools/hooks/cryptroot
 
#-------------------------------------------------------------------------------------------------------------------
    cat > /etc/initramfs-tools/hooks/clean_cryptroot << '__EOF__'
#!/bin/sh
 
# Create /etc/crypttab
# Trying to use main decrypt_derived script, but /usr/share/initramfs-tools/hooks/cryptroot
# seems to be duplicating the :rsvd entry from /etc/crypttab. Every time :rsvd is used as a
# key, it gets added to the list of devices to be put into /etc/initramfs-tools/conf.d/cryptroot
# So ugly workaround - script to remove dupes from cryptroot
   
PREREQ="cryptroot"
 
prereqs() {
        echo "$PREREQ"
}
 
case $1 in
# get pre-requisites
prereqs)
        prereqs
        exit 0
        ;;
esac
 
. /usr/share/initramfs-tools/hook-functions
 
# Need to make sure that :rsvd is at the top since that has to be unlocked first.
# Then it uses the derived_key from that to unlock the rest of the devices
cat ${DESTDIR}/conf/conf.d/cryptroot | fgrep ":rsvd,source" | uniq > ${DESTDIR}/conf/conf.d/cryptroot.sorted
cat ${DESTDIR}/conf/conf.d/cryptroot | fgrep ":rsvd,keyscript" >> ${DESTDIR}/conf/conf.d/cryptroot.sorted
mv ${DESTDIR}/conf/conf.d/cryptroot.sorted ${DESTDIR}/conf/conf.d/cryptroot
__EOF__
    chmod +x /etc/initramfs-tools/hooks/clean_cryptroot
 
#-------------------------------------------------------------------------------------------------------------------
    # Need to copy detached headers when creating initramfs - NOTE: Detached headers not quite working yet
    if [ "ZZ${DETACHEDHEADERS}" = "ZZy" ]; then
        cat > /etc/initramfs-tools/hooks/copy_cryptheaders << '__EOF__'
#!/bin/sh
 
PREREQ="cryptroot"
 
prereqs() {
        echo "$PREREQ"
}
 
case $1 in
# get pre-requisites
prereqs)
        prereqs
        exit 0
        ;;
esac
 
. /usr/share/initramfs-tools/hook-functions
 
if [ ! -d "$DESTDIR/headers" ]; then
        mkdir -p "$DESTDIR/headers"
fi
 
for header in  "/root/headers/*" ; do
        copy_exec ${header} headers
done
__EOF__
        chmod +x /etc/initramfs-tools/hooks/copy_cryptheaders
 
        ######## Detached headers
        # RSVD - LUKS-header-${BOXNAME}:rsvd.luksheader
        # SWAP - LUKS-header-${BOXNAME}:swap.luksheader
        # ROOT - LUKS-header-${DISKS[${DISK}]}${PARTITION_DATA}.luksheader
 
        echo "${BOXNAME}:rsvd   UUID=$(blkid ${RSVDDEVRAW} -s UUID -o value)    none    luks,header=/root/headers/LUKS-header-${BOXNAME}:rsvd.luksheader" >> /etc/crypttab
        if [ ${SIZE_SWAP} ] && [ ${SIZE_SWAP} != 0 ]; then
            echo "${BOXNAME}:swap   UUID=$(blkid ${SWAPDEVRAW} -s UUID -o value)    ${BOXNAME}:rsvd luks,noauto,keyscript=/etc/initramfs-tools/scripts/luks/decrypt_derived,header=/root/headers/LUKS-header-${BOXNAME}:swap.luksheader" >> /etc/crypttab
        fi
        for DISK in `seq 1 ${#DISKS[@]}` ; do
            echo "root_crypt${DISK} UUID=$(blkid ${DISKS[${DISK}]}${PARTITION_DATA} -s UUID -o value)  ${BOXNAME}:rsvd luks,noauto,keyscript=/etc/initramfs-tools/scripts/luks/decrypt_derived,header=/root/headers/LUKS-header-${DISKS[${DISK}]}${PARTITION_DATA}.luksheader" >> /etc/crypttab
        done
    else
        echo "${BOXNAME}:rsvd   UUID=$(blkid ${RSVDDEVRAW} -s UUID -o value)    none    luks" >> /etc/crypttab
        if [ ${SIZE_SWAP} ] &&[ ${SIZE_SWAP} != 0 ]; then
            # echo "${BOXNAME}:swap UUID=$(blkid ${SWAPDEVRAW} -s UUID -o value)    none    luks,noauto,keyscript=/etc/initramfs-tools/scripts/luks/get.root_crypt.decrypt_derived" >> /etc/crypttab
            echo "${BOXNAME}:swap   UUID=$(blkid ${SWAPDEVRAW} -s UUID -o value)    ${BOXNAME}:rsvd luks,noauto,keyscript=/etc/initramfs-tools/scripts/luks/decrypt_derived" >> /etc/crypttab
        fi
        for DISK in `seq 1 ${#DISKS[@]}` ; do
            # echo "root_crypt${DISK}   UUID=$(blkid ${DISKS[${DISK}]}${PARTITION_DATA} -s UUID -o value)  none    luks,noauto,keyscript=/etc/initramfs-tools/scripts/luks/get.root_crypt.decrypt_derived" >> /etc/crypttab
            echo "root_crypt${DISK} UUID=$(blkid ${DISKS[${DISK}]}${PARTITION_DATA} -s UUID -o value)  ${BOXNAME}:rsvd luks,noauto,keyscript=/etc/initramfs-tools/scripts/luks/decrypt_derived" >> /etc/crypttab
        done
    fi # detached headers
 
#-------------------------------------------------------------------------------------------------------------------
   
#############################################
## Testing using main ubuntu scripts, so don't create initramfs cryptroot
## Leaving this here just in case we need to use it at some point
cat > /dev/null << '__EOF__'
    # Create initramfs cryptroot
    echo "target=${BOXNAME}:rsvd,source=UUID=$(blkid ${RSVDDEVRAW} -s UUID -o value),key=none" > /etc/initramfs-tools/conf.d/cryptroot
 
    if [ ${SIZE_SWAP} ] &&[ ${SIZE_SWAP} != 0 ]; then
        echo "" >> /etc/initramfs-tools/conf.d/cryptroot
        echo "### target=${BOXNAME}:swap,source=UUID=$(blkid ${SWAPDEVRAW} -s UUID -o value),key=none,discard,keyscript=/scripts/luks/get.root_crypt.decrypt_derived" >> /etc/initramfs-tools/conf.d/cryptroot
    fi
 
    echo "" >> /etc/initramfs-tools/conf.d/cryptroot
    for DISK in `seq 1 ${#DISKS[@]}` ; do
        echo "### target=root_crypt${DISK},source=UUID=$(blkid ${DISKS[${DISK}]}${PARTITION_DATA} -s UUID -o value),rootdev,keyscript=/scripts/luks/get.root_crypt.decrypt_derived" >> /etc/initramfs-tools/conf.d/cryptroot
    done
__EOF__
#############################################
   
    # make sure that openssh-server is installed before installing dropbear
    apt-get -qq -y install openssh-server
    apt-get -qq -y install dropbear
 
#-------------------------------------------------------------------------------------------------------------------
##### Force dropbear to use dhcp - can also set up real IP
    cat > /etc/initramfs-tools/conf.d/dropbear_network << '__EOFF__'
# dropbear doesn't use IP=dhcp anymore - it just defaults to dhcp
# export IP=dhcp
DROPBEAR=y
CRYPTSETUP=y
__EOFF__
 
##### Not using busybox, using klibc
## sed -i 's/^BUSYBOX=.*/BUSYBOX=n/' /etc/initramfs-tools/initramfs.conf
 
#-------------------------------------------------------------------------------------------------------------------
##### Need the full version of busybox if we use it
    cat > /etc/initramfs-tools/hooks/busybox2 << '__EOFF__'
#!/bin/sh
##### Need the full version of busybox if we use it
 
PREREQ=""
 
prereqs() {
        echo "$PREREQ"
}
 
case $1 in
# get pre-requisites
prereqs)
        prereqs
        exit 0
        ;;
esac
 
# busybox
if [ "${BUSYBOX}" != "n" ] && [ -e /bin/busybox ]; then
    . /usr/share/initramfs-tools/hook-functions
    rm -f ${DESTDIR}/bin/busybox
    copy_exec /bin/busybox /bin
    copy_exec /usr/bin/xargs /bin
fi
__EOFF__
    chmod +x /etc/initramfs-tools/hooks/busybox2
 
#-------------------------------------------------------------------------------------------------------------------
##### Create script to start md arrays no matter what
    cat > /etc/initramfs-tools/scripts/init-premount/zzmdraidforce <<'__EOF__'
#!/bin/sh
 
# start md arrays no matter what
 
PREREQ=""
prereqs() {
        echo "$PREREQ"
}
case "$1" in
    prereqs)
         prereqs
         exit 0
    ;;
esac
. /scripts/functions
 
sleep 10
echo "Looking for inactive arrays ..."
cat /proc/mdstat
echo ""
i=0;
for md in $(cat /proc/mdstat | grep inactive | cut -d" " -f1); do
    devs="$(cat /proc/mdstat | grep ^${md} | cut -d" " -f5- | sed -e 's/\[[0-9]\]//g' -e 's/sd/\/dev\/sd/g')"
    echo "${md} is inactive. Devices: ${devs}"
    echo "Stopping ${md} ..."
    mdadm --stop /dev/${md}
    echo "Assembling ${md} ..."
    mdadm --assemble /dev/${md} ${devs} || ( echo "Assembling ${md} (--force) ..."; mdadm --assemble --force /dev/${md} ${devs})
    echo ""
    i=$(( ${i} + 1 ))
done
echo ""
if [ $i -gt 0 ]; then
    echo "${i} arrays were inactive."
    echo "/proc/mdstat is now:"
    cat /proc/mdstat
    sleep 5
else
    echo "All arrays seem to be active"
fi
echo ""
__EOF__
 
# Make it executable
chmod a+x /etc/initramfs-tools/scripts/init-premount/zzmdraidforce
 
#-------------------------------------------------------------------------------------------------------------------
##### Unlock script for dropbear in initramfs
    cat > /etc/initramfs-tools/hooks/mount_cryptroot << '__EOFF__'
#!/bin/sh
 
# This script generates two scripts in the initramfs output,
# /root/mount_cryptroot.sh and /root/.profile
# https://projectgus.com/2013/05/encrypted-rootfs-over-ssh-with-debian-wheezy/
 
ALLOW_SHELL=1
# Set this to 1 before running update-initramfs if you want
# to allow authorized users to type Ctrl-C to drop to a
# root shell (useful for debugging, potential for abuse.)
#
# (Note that even with ALLOW_SHELL=0 it may still be possible
# to achieve a root shell.)
 
PREREQ="dropbear"
prereqs() {
    echo "$PREREQ"
}
case "$1" in
    prereqs)
        prereqs
        exit 0
    ;;
esac
 
. "${CONFDIR}/initramfs.conf"
. /usr/share/initramfs-tools/hook-functions
 
if [ -z ${DESTDIR} ]; then
    exit
fi
 
# 16.04/xenial uses a tempdir for /root homedir, so need to find which one it is
# something like /root-2EpTFt/
ROOTDIR=`ls -1d ${DESTDIR}/root* | tail -1`
SCRIPT="${ROOTDIR}/mount_cryptroot.sh"
cat > "${SCRIPT}" << 'EOF'
#!/bin/sh
CMD=
while [ -z "$CMD" -o -z "`pidof askpass plymouth`" ]; do
  # force use of busybox for ps
  CMD=`busybox ps -o args | grep cryptsetup | grep -i open | grep -v grep`
  # Not using busybox, using klibc
  # CMD=`ps -o args | grep cryptsetup | grep -i open | grep -v grep`
 
  sleep 0.1
done
while [ -n "`pidof askpass plymouth`" ]; do
  $CMD && kill -9 `pidof askpass plymouth` && echo "Success"
done
EOF
 
chmod +x "${SCRIPT}"
 
# Run mount_cryptroot by default and close the login session afterwards
# If ALLOW_SHELL is set to 1, you can press Ctrl-C to get to an interactive prompt
cat > "${ROOTDIR}/.profile" << EOF
ctrl_c_exit() {
  exit 1
}
ctrl_c_shell() {
  # Ctrl-C during .profile appears to mangle terminal settings
  reset
}
if [ "$ALLOW_SHELL" == "1" ]; then
  echo "Unlocking rootfs... Type Ctrl-C for a shell."
  trap ctrl_c_shell INT
else
  echo "Unlocking rootfs..."
  trap ctrl_c_exit INT
fi
${ROOTDIR#$DESTDIR}/mount_cryptroot.sh && exit 1 || echo "Run ./mount_cryptroot.sh to try unlocking again"
trap INT
EOF
__EOFF__
    chmod +x /etc/initramfs-tools/hooks/mount_cryptroot
 
#-------------------------------------------------------------------------------------------------------------------
    ##### Second script to handle converting SSH keys.
    # You might NOT want to use this as now your SSH keys are stored inside
    # plaintext initramfs instead of only encypted volume.
    cat > /etc/initramfs-tools/hooks/dropbear.fixup2 <<'__EOFF__'
#!/bin/sh
PREREQ="dropbear"
prereqs() {
    echo "$PREREQ"
}
case "$1" in
    prereqs)
        prereqs
        exit 0
    ;;
esac
   
. "${CONFDIR}/initramfs.conf"
. /usr/share/initramfs-tools/hook-functions
   
# Convert SSH keys
if [ "${DROPBEAR}" != "n" ] && [ -r "/etc/crypttab" ] ; then
    echo "----- Installing host SSH keys into dropbear initramfs -----"
    # /usr/lib/dropbear/dropbearconvert openssh dropbear /etc/ssh/ssh_host_dsa_key ${DESTDIR}/etc/dropbear/dropbear_dss_host_key
    /usr/lib/dropbear/dropbearconvert openssh dropbear /etc/ssh/ssh_host_rsa_key ${DESTDIR}/etc/dropbear/dropbear_rsa_host_key
    /usr/lib/dropbear/dropbearconvert openssh dropbear /etc/ssh/ssh_host_ecdsa_key ${DESTDIR}/etc/dropbear/dropbear_ecdsa_host_key
fi
__EOFF__
 
# Make it executable
chmod a+x /etc/initramfs-tools/hooks/dropbear.fixup2
 
#-------------------------------------------------------------------------------------------------------------------
    # Put SSH pubkey in initramfs
    echo "-----------------------------------------------------------------------------"
    echo "Installing sshpubkey ${SSHPUBKEY} and ${GITPUBKEYS} pubkey(s) into dropbear initramfs"
    [ ! -e /etc/initramfs-tools/root/.ssh ] && mkdir -p /etc/initramfs-tools/root/.ssh
    echo "${SSHPUBKEY}" >> /etc/initramfs-tools/root/.ssh/authorized_keys
    for GITKEY in ${GITPUBKEYS} ; do
        echo "####### Github ${GITKEY} keys #######" >> /etc/initramfs-tools/root/.ssh/authorized_keys
        echo "$(wget --quiet -O- https://github.com/${GITKEY}.keys)" >> /etc/initramfs-tools/root/.ssh/authorized_keys
        echo "####### Github ${GITKEY} keys #######" >> /etc/initramfs-tools/root/.ssh/authorized_keys
        echo "#" >> /etc/initramfs-tools/root/.ssh/authorized_keys
    done
    echo "-----------------------------------------------------------------------------"
   
fi # if LUKS
 
#-------------------------------------------------------------------------------------------------------------------
# udev rule to enable seeing vmware scsi disks
cat > /etc/udev/rules.d/99-vmware.rules << "EOF"
# VMWare SCSI devices have no serial - use VMWARE_ and device ID as serial
KERNEL=="sd*[!0-9]|sr*", ENV{ID_VENDOR}=="VMware_" IMPORT{program}="scsi_id --export --whitelisted -d $devnode", ENV{ID_SERIAL}="VMWARE_%k"
 
KERNEL=="sd*|sr*", ENV{DEVTYPE}=="disk", ENV{ID_SERIAL}=="?*", SYMLINK+="disk/by-id/$env{ID_BUS}-$env{ID_SERIAL}"
 
KERNEL=="sd*", ENV{DEVTYPE}=="partition", ENV{ID_SERIAL}=="?*", SYMLINK+="disk/by-id/$env{ID_BUS}-$env{ID_SERIAL}-part%n"
 
# ----------------------------- scsi type disk
# ID_SCSI=1
# ID_VENDOR=VMware_
# ID_VENDOR_ENC=VMware\x2c\x20
# ID_MODEL=VMware_Virtual_S
# ID_MODEL_ENC=VMware\x20Virtual\x20S
# ID_REVISION=1.0
# ID_TYPE=disk
# ----------------------------- sata type disk
# ID_SCSI=1
# ID_VENDOR=ATA
# ID_VENDOR_ENC=ATA\x20\x20\x20\x20\x20
# ID_MODEL=VMware_Virtual_S
# ID_MODEL_ENC=VMware\x20Virtual\x20S
# ID_REVISION=0001
# ID_TYPE=disk
# ID_SERIAL=35000c293157635fb
# ID_SERIAL_SHORT=5000c293157635fb
# ID_WWN=0x5000c293157635fb
# ID_WWN_WITH_EXTENSION=0x5000c293157635fb
# ID_SCSI_SERIAL=00000000000000000001
EOF
 
# This from https://bugs.launchpad.net/ubuntu/+source/zfs-initramfs/+bug/1530953
# Also https://github.com/zfsonlinux/pkg-zfs/wiki/HOWTO-install-Ubuntu-14.04---15.04-to-a-Native-ZFS-Root-Filesystem
echo 'KERNEL=="sd*[0-9]", IMPORT{parent}=="ID_*", ENV{ID_FS_TYPE}=="zfs_member", SYMLINK+="$env{ID_BUS}-$env{ID_SERIAL}-part%n"' > /etc/udev/rules.d/61-zfs-vdev.rules
 
# https://bugs.launchpad.net/ubuntu/+source/zfs-initramfs/+bug/1530953/comments/28
# HRM - this one isn't working
# echo 'KERNEL=="sd*[0-9]", IMPORT{parent}=="ID_*", ENV{ID_PART_ENTRY_SCHEME}=="gpt", ENV{ID_PART_ENTRY_TYPE}=="6a898cc3-1dd2-11b2-99a6-080020736631", SYMLINK+="$env{ID_BUS}-$env{ID_SERIAL}-part%n"' > /etc/udev/rules.d/60-zfs-vdev.rules
 
 
#-------------------------------------------------------------------------------------------------------------------
##### Script to shutdown initramfs network before passing control to regular Ubuntu scripts
# Without this network config from initramfs is used forever plus causes extra
# few minutes of delay plus errors on bootup.
cat > /etc/initramfs-tools/scripts/init-bottom/network-down << '__EOFF__'
#!/bin/sh
 
PREREQ=""
 
prereqs() {
        echo "$PREREQ"
}
 
case $1 in
# get pre-requisites
prereqs)
        prereqs
        exit 0
        ;;
esac
# Shutdown initramfs network before passing control to regular Ubuntu scripts
# Without this network config from initramfs is used forever plus causes extra
# few minutes of delay plus errors on bootup.
ifconfig eth0 0.0.0.0 down
__EOFF__
chmod +x /etc/initramfs-tools/scripts/init-bottom/network-down
 
#-------------------------------------------------------------------------------------------------------------------
# Create fstab
echo "tmpfs                   /tmp    tmpfs   defaults,noatime,mode=1777      0 0" >> /etc/fstab
 
if [ ${SIZE_ZVOL} ] && [ ${SIZE_ZVOL} != 0 ]; then
    echo "" >> /etc/fstab
    echo "# ${BOXNAME}_zwap is the zfs SWAP zvol" >> /etc/fstab
    echo "/dev/zvol/${POOLNAME}/SWAP    none    swap    defaults                        0 0" >> /etc/fstab
fi
 
if [ ${SIZE_SWAP} ] && [ ${SIZE_SWAP} != 0 ]; then
    echo "" >> /etc/fstab
    echo "# ${BOXNAME}_swap is the mdadm array of partition ${PARTITION_SWAP} on all drives" >> /etc/fstab
    echo "UUID=$(blkid -t LABEL=${BOXNAME}_swap -s UUID -o value) none swap defaults   0 0" >>/etc/fstab
fi
 
if [ "ZZ${UEFI}" = "ZZy" ]; then
    echo "" >> /etc/fstab
    echo "UUID=$(blkid -t LABEL=${BOXNAME}_efi -s UUID -o value) /boot/efi vfat defaults  0 1" >>/etc/fstab
 
    #for DISK in `seq 1 ${#DISKS[@]}` ; do
    #   echo "UUID=$(blkid -t LABEL=EFI_${DISK} -s UUID -o value) /boot/efi_${DISK} vfat defaults  0 1" >>/etc/fstab
    #done
fi
 
#-------------------------------------------------------------------------------------------------------------------
# Set GRUB to use VBE and framebuffer for 16.04
if [ ${SUITE} = xenial ]; then
    cat >> /etc/default/grub << '__EOF__'
 
# https://onetransistor.blogspot.com/2016/03/plymouth-fix-nvidia.html
# Also see /etc/initramfs-tools/conf.d/splash
GRUB_GFXPAYLOAD_LINUX="keep"
GRUB_VIDEO_BACKEND="vbe"
GRUB_GFXMODE="800x600x32"
__EOF__
    echo "FRAMEBUFFER=y" > /etc/initramfs-tools/conf.d/splash
   
    # Manually enable solar theme (cuz I like it), and update-alternatives doesn't show it
    # The flares don't work on bootup, boo hiss, although they do work on shutdown.  WTF ?
    # Actually, they work until the password prompt is put up.  Double WTF ?
    rm -f /etc/alternatives/default.plymouth
    ln -s /usr/share/plymouth/themes/solar/solar.plymouth /etc/alternatives/default.plymouth
fi
 
# Set GRUB to use zfs - enable zswap if USE_ZSWAP="zswap parameters"
# Also disabling persistent interface names, sticking to eth0 and so on
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT=\"net.ifnames=0 biosdevname=0 rpool=${POOLNAME} bootfs=${POOLNAME}\/ROOT\/ubuntu boot=zfs bootdegraded=true ${USE_ZSWAP} splash\"/" /etc/default/grub
# If using zswap enable lz4 compresstion
if [ "ZZ${USE_ZSWAP}" != "ZZ" ]; then
    echo "lz4" >> /etc/modules
    echo "lz4" >> /etc/initramfs-tools/modules
fi
 
#-------------------------------------------------------------------------------------------------------------------
# Export and import boot zpool to populate /etc/zfs/zpool.cache if using LUKS
if [ "ZZ${LUKS}" = "ZZy" ]; then
    zpool export boot
    zpool import -f -d /dev/disk/by-id boot
fi
 
#-------------------------------------------------------------------------------------------------------------------
# Clear existing EFI NVRAM boot order, it's more than likely incorrect for our needs by now
# Also sets 10 second timeout for EFI boot menu just in case it was set to too low value earlier
# NOTE: Most information for EFI install comes from here :
#   http://blog.asiantuntijakaveri.fi/2014/12/headless-ubuntu-1404-server-with-full.html
if [ -e /sys/firmware/efi ]; then
    efibootmgr --delete-bootorder --timeout 10 --write-signature
 
    # Remove unwanted, existing boot entries from EFI list
    for f in `seq 0 6`; do
        efibootmgr --delete-bootnum --bootnum 000${f}
    done
fi
 
#-------------------------------------------------------------------------------------------------------------------
# Create grub device.map for just install drives - eg.
# grub-mkdevicemap -nvv
# (hd0) ata-VBOX_HARDDISK_VB7e33e873-e3c9fd91
# (hd1) ata-VBOX_HARDDISK_VB3f3328bd-1d7db667
# (hd2) ata-VBOX_HARDDISK_VB11f330ab-76c3340a
#
# We do this manually rather than grub-mkdevicemap to ensure we only use the disks
# listed in ZFS-setup.disks.txt, in case there are other disks in the system
echo "" > /boot/grub/device.map
for DISK in `seq 1 ${#DISKS[@]}` ; do
    HD=$(($DISK - 1))
    echo "(hd${HD}) ${DISKS[${DISK}]}" >> /boot/grub/device.map
done
# cat /boot/grub/device.map
 
# Install and update grub  https://ubuntuforums.org/showthread.php?t=2223856&page=3
for DISK in `seq 1 ${#DISKS[@]}` ; do
    sgdisk -C ${DISKS[${DISK}]}
    sgdisk -h ${PARTITION_GRUB} ${DISKS[${DISK}]}
   
##  if [ "ZZ${UEFI}" = "ZZy" ]; then
##      mkdir -p /boot/efi_${DISK}
##      mount /boot/efi_${DISK}
##     
##      # Install grub to EFI system partition
##      echo "Ignore errors from grub-install here if not in EFI mode"
##      grub-install --boot-directory=/boot --bootloader-id="ZFS-${DISK}" --no-floppy --recheck --target=x86_64-efi --efi-directory=/boot/efi_${DISK} ${DISKS[${DISK}]}
##  fi
    grub-install --target=i386-pc ${DISKS[${DISK}]}
done
 
#-------------------------------------------------------------------------------------------------------------------
if [ "ZZ${UEFI}" = "ZZy" ]; then
    mkdir -p /boot/efi
    mount /boot/efi
 
    # Install grub to EFI system partition
    echo "Ignore errors from grub-install here if not in EFI mode"
    grub-install --boot-directory=/boot --bootloader-id="ZFS" --no-floppy --recheck --target=x86_64-efi --efi-directory=/boot/efi /dev/md/${BOXNAME}:efi
 
##  # Make disks bootable on non-EFI system
##  for DISK in `seq 1 ${#DISKS[@]}` ; do
##      mkdir -p /boot/efi_${DISK}/EFI/BOOT
##      cp -a "/boot/efi_${DISK}/EFI/ZFS-${DISK}/grubx64.efi" /boot/efi_${DISK}/EFI/BOOT/bootx64.efi
##      [ -d /sys/firmware/efi ] && efibootmgr --create --disk ${DISKS[${DISK}]} --part ${PARTITION_EFI} --write-signature --loader '\EFI\BOOT\bootx64.efi' --label "EFI fallback disk ${DISK}"
##  done
 
    mkdir -p /boot/efi/EFI/BOOT
    # Get EFI shell
    wget --no-proxy -O /boot/efi/shellx64.efi https://svn.code.sf.net/p/edk2/code/trunk/edk2/EdkShellBinPkg/FullShell/X64/Shell_Full.efi
    cp /boot/efi/shellx64.efi /boot/efi/EFI/BOOT
    cp -a "/boot/efi/EFI/ZFS/grubx64.efi" /boot/efi/EFI/BOOT/bootx64.efi
 
    for DISK in `seq 1 ${#DISKS[@]}` ; do
        [ -d /sys/firmware/efi ] && efibootmgr --create --disk ${DISKS[${DISK}]} --part ${PARTITION_EFI} --write-signature --loader '\EFI\BOOT\bootx64.efi' --label "EFI fallback disk ${DISK}"
 
        # grub-install here should build entries in bootmgr - equivalent efibootmgr cmd below
        grub-install --boot-directory=/boot --bootloader-id="ZFS-${DISK}" --no-floppy --recheck --target=x86_64-efi --efi-directory=/boot/efi_${DISK} ${DISKS[${DISK}]}
        ## [ -d /sys/firmware/efi ] && efibootmgr --create --disk ${DISKS[${DISK}]} --part ${PARTITION_EFI} --write-signature --loader '\EFI\ZFS\grubx64.efi' --label "ZFS-${DISK}"
    done
 
##  # Create grub.cfg
##  grub-mkconfig -o /boot/efi_1/EFI/grub.cfg
##  for DISK in `seq 2 ${#DISKS[@]}` ; do
##      cp -a /boot/efi_1/EFI/grub.cfg /boot/efi_${DISK}/EFI
##  done
    grub-mkconfig -o /boot/efi/EFI/grub.cfg
 
fi #UEFI
update-grub
 
### Re-order EFI boot order
##if [ "ZZ${UEFI}" = "ZZy" ]; then
##  for DISK in `seq 1 ${#DISKS[@]}` ; do
##      umount /boot/efi_${DISK}
##  done
## 
##  # 2 entries per disk - regular in /boot/efi_X/EFI/ZFS-X and fallback in /boot/efi_X/BOOT
##  EFIENTRIES=$(( ${#DISKS[@]} * 2 ))
##  EFIORDER="0"
##  for ENTRY in `seq 1 $(( ${EFIENTRIES} - 1 ))` ; do
##      EFIORDER="${EFIORDER},${ENTRY}"
##  done
##  [ -d /sys/firmware/efi ] && efibootmgr --bootorder ${EFIORDER}
##fi
 
#-------------------------------------------------------------------------------------------------------------------
# Nicer PS1 prompt
cat >> /etc/bash.bashrc << EOF
 
PS1="${debian_chroot:+($debian_chroot)}\[\$(tput setaf 2)\]\u@\[\$(tput bold)\]\[\$(tput setaf 5)\]\h\[\$(tput sgr0)\]\[\$(tput setaf 7)\]:\[\$(tput bold)\]\[\$(tput setaf 4)\]\w\[\$(tput setaf 7)\]\\$ \[\$(tput sgr0)\]"
 
# https://unix.stackexchange.com/questions/99325/automatically-save-bash-command-history-in-screen-session
PROMPT_COMMAND="history -a; history -c; history -r; \${PROMPT_COMMAND}"
HISTSIZE=5000
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
EOF
cat >> /etc/skel/.bashrc << EOF
 
PS1="${debian_chroot:+($debian_chroot)}\[\$(tput setaf 2)\]\u@\[\$(tput bold)\]\[\$(tput setaf 5)\]\h\[\$(tput sgr0)\]\[\$(tput setaf 7)\]:\[\$(tput bold)\]\[\$(tput setaf 4)\]\w\[\$(tput setaf 7)\]\\$ \[\$(tput sgr0)\]"
 
# https://unix.stackexchange.com/questions/99325/automatically-save-bash-command-history-in-screen-session
PROMPT_COMMAND="history -a; history -c; history -r; \${PROMPT_COMMAND}"
HISTSIZE=5000
alias ls='ls --color=auto'
alias l='ls -la'
alias lt='ls -lat | head -25'
alias vhwinfo='wget --no-check-certificate https://vhwinfo.com/vhwinfo.sh -O - -o /dev/null|bash'
EOF
cat >> /root/.bashrc << "EOF"
# PS1='\[\033[01;37m\]\[\033[01;41m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ '
PS1='\[\033[01;37m\]\[\033[01;41m\]\u@\[\033[00m\]\[$(tput bold)\]\[$(tput setaf 5)\]\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ '
 
# https://unix.stackexchange.com/questions/99325/automatically-save-bash-command-history-in-screen-session
PROMPT_COMMAND="history -a; history -c; history -r; ${PROMPT_COMMAND}"
HISTSIZE=5000
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
EOF
 
cat > /root/.bash_aliases << EOF
alias ls='ls --color=auto'
alias l='ls -la'
alias lt='ls -lat | head -25'
alias vhwinfo='wget --no-check-certificate https://vhwinfo.com/vhwinfo.sh -O - -o /dev/null|bash'
EOF
 
#-------------------------------------------------------------------------------------------------------------------
# Create user and apply Custom config script if defined
# Not using --create-home as dir should already exist as a zfs dataset
# -M to prevent it from trying to create a home dir
useradd -c "${UCOMMENT}" -p $(echo "${UPASSWORD}" | mkpasswd -m sha-512 --stdin) -M --home-dir /home/${USERNAME} --user-group --groups adm,sudo,dip,plugdev --shell /bin/bash ${USERNAME}
# Since /etc/skel/* files aren't copied, have to do it manually
rsync -a /etc/skel/ /home/${USERNAME}
 
mkdir -p /root/.ssh /home/${USERNAME}/.ssh
echo "${SSHPUBKEY}" >> /root/.ssh/authorized_keys
for GITKEY in ${GITPUBKEYS} ; do
    echo "####### Github ${GITKEY} keys #######" >> /root/.ssh/authorized_keys
    echo "$(wget --quiet -O- https://github.com/${GITKEY}.keys)" >> /root/.ssh/authorized_keys
    echo "####### Github ${GITKEY} keys #######" >> /root/.ssh/authorized_keys
    echo "#" >> /root/.ssh/authorized_keys
done
cp /root/.ssh/authorized_keys /home/${USERNAME}/.ssh
chmod 700 /root/.ssh /home/${USERNAME}/.ssh
chown -R ${USERNAME}.${USERNAME} /home/${USERNAME}
 
#-------------------------------------------------------------------------------------------------------------------
# Now finally make an initramfs
# Ugly hack to get kernel version
KVER=$(basename $(ls -1 /boot/vmlinuz* | sort -rn) | sed -e 's/vmlinuz-//')
rm -fv /tmp/fakestart/update-initramfs
update-initramfs -c -k ${KVER}
update-grub
 
# Final update - make sure we don't overwrite modified config files like bash.bashrc
# https://askubuntu.com/questions/104899/make-apt-get-or-aptitude-run-with-y-but-not-prompt-for-replacement-of-configu
apt-get -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -f install
apt-get -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --allow-downgrades --allow-remove-essential upgrade
apt-get -qq -y clean
apt-get -qq -y autoclean
apt-get -qq -y autoremove
rm -rf /var/lib/apt/lists/*
 
#-------------------------------------------------------------------------------------------------------------------
# Run Custom script to install user-chosen stuff and configurations - take snapshot first
if [ "${CUSTOMSCRIPT}ZZ" != "ZZ" ] ; then
    echo "Running custom script Setup-Custom.sh (from ${CUSTOMSCRIPT})"
    zfs snap ${POOLNAME}/ROOT/ubuntu@Pre-Custom
    eval /root/Setup-Custom.sh
fi
 
exit
__EOFSETUP__
chmod +x /mnt/zfs/root/Setup.sh
# ======== END create Setup.sh script ===============================================================
 
# Here are a couple of helper scripts
# Replace-failed-drive.sh - goes into /root in new system, helps to replace a failed drive
#                         - NOTE: not complete yet
# Reboot-testing.sh       - goes into /root in local system, helps to enter/exit chroot
#                           for new system for debugging
 
# ============= Replacing drive helper script ====================================================
# Script to help in replacing a failed drive - goes in new /mnt/zfs system root dir
cat > /mnt/zfs/root/Replace-failed-drive.sh << '__EOFREPLACE__'
#!/bin/bash
 
# If you're using this script, then one of the drives has failed.  You need to define a few
# things here : GOODDISK, NEWDISK and NEW
 
# These were the drives that were installed initially
__EOFREPLACE__
 
for DISK in `seq 1 ${#DISKS[@]}` ; do
    echo "DISKS[${DISK}]=${DISKS[${DISK}]}" >> /mnt/zfs/root/Replace-failed-drive.sh
done
 
cat >> /mnt/zfs/root/Replace-failed-drive.sh << __EOFREPLACE1__
 
# Representative good disk - this is the source of a good partition table
# Used to create a new partition table on the NEWDISK defined below
export GOODDISK=ata-VBOX_HARDDISK_VB2d8b0815-33f95506<<--This-is-a-sample
 
# New replacement disk
export NEWDISK=ata-VBOX_HARDDISK_VBc6d3eb9a-d59c8e36<<--This-is-a-sample
 
# Suffix for new partitions and /boot/efi_ directory
NEW=NEW
 
# NOTE: These definitions above are just *REPRESENTATIVE* - you need to fill in your
#       own real disk definitions from /dev/disk/by-id
 
## For testing, you can offline/delete a drive, /dev/sdc
##
## Should unmount the /boot/efi_X before deleting the drive
#  umount /boot/efi_X
##
#  readlink /sys/block/sdc
## ../devices/pci0000:00/0000:00:0d.0/ata6/host5/target5:0:0/5:0:0:0/block/sdc
##                                         ^^^^^
## Force disconnect of drive
#  echo 1 > /sys/block/sdX/device/delete
##                     ^^^
## Trigger rescan of a given port
#  echo "- - -" > /sys/class/scsi_host/host5/scan
##                                     ^^^^^
 
export BOXNAME=${BOXNAME}
export POOLNAME=${POOLNAME}
export LUKS=${LUKS}
export RANDOMIZE=${RANDOMIZE}
export UEFI=${UEFI}
export SIZE_SWAP=${SIZE_SWAP}
export PASSPHRASE=${PASSPHRASE}
export PARTITION_EFI=${PARTITION_EFI}
export PARTITION_GRUB=${PARTITION_GRUB}
export PARTITION_BOOT=${PARTITION_BOOT}
export PARTITION_SWAP=${PARTITION_SWAP}
export PARTITION_DATA=${PARTITION_DATA}
export PARTITION_RSVD=${PARTITION_RSVD}
__EOFREPLACE1__
 
cat >> /mnt/zfs/root/Replace-failed-drive.sh << '__EOFREPLACE2__'
 
if [ ${NEWDISK} = "ata-VBOX_HARDDISK_VBc6d3eb9a-d59c8e36<<--This-is-a-sample" ] ; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!!  Must edit GOODDISK and NEWDISK variables  !!"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
fi
 
exec > >(tee -a /root/Replace-failed-drive.log) 2>&1
 
# Randomize entire disk
if [ "ZZ${RANDOMIZE}" = "ZZy" ]; then
    # urandom is limited, so use frandom module
    [ ! -e /var/lib/dpkg/info/build-essential.list ] && apt-get -qq -y install build-essential
    if [ ! -e /usr/src/frandom ]; then
        mkdir -p /usr/src/frandom
        wget --no-proxy http://billauer.co.il/download/frandom-1.1.tar.gz -O /usr/src/frandom/frandom-1.1.tar.gz
        tar --directory /usr/src/frandom -xvzf /usr/src/frandom/frandom-1.1.tar.gz
    fi
    cd /usr/src/frandom/frandom-1.1
    rm -f *o
    make
    install -m 644 frandom.ko /lib/modules/`uname -r`/kernel/drivers/char/
    depmod -a
    modprobe frandom
 
    dd if=/dev/frandom of=${NEWDISK} bs=512 count=$(blockdev --getsz ${NEWDISK}) &
    WAITPIDS="${WAITPIDS} "$!
fi
 
# Clear any old zpool info
zpool labelclear -f ${NEWDISK} > /dev/null 2>&1
[ -e ${NEWDISK}${PARTITION_DATA} ] && zpool labelclear -f ${NEWDISK}${PARTITION_DATA} > /dev/null 2>&1
 
mdadm --zero-superblock --force ${NEWDISK}*
[ -e ${NEWDISK}${PARTITION_BOOT} ] && mdadm --zero-superblock --force ${NEWDISK}${PARTITION_BOOT} > /dev/null 2>&1
[ -e ${NEWDISK}${PARTITION_SWAP} ] && mdadm --zero-superblock --force ${NEWDISK}${PARTITION_SWAP} > /dev/null 2>&1
[ -e ${NEWDISK}${PARTITION_RSVD} ] && mdadm --zero-superblock --force ${NEWDISK}${PARTITION_RSVD} > /dev/null 2>&1
 
# Clear any old LUKS or mdadm info
[ -e ${NEWDISK}${PARTITION_DATA} ] && dd if=/dev/zero of=${NEWDISK}${PARTITION_DATA} bs=512 count=20480 > /dev/null 2>&1
[ -e ${NEWDISK}${PARTITION_SWAP} ] && dd if=/dev/zero of=${NEWDISK}${PARTITION_SWAP} bs=512 count=20480 > /dev/null 2>&1
[ -e ${NEWDISK}${PARTITION_RSVD} ] && dd if=/dev/zero of=${NEWDISK}${PARTITION_RSVD} bs=512 count=4096 > /dev/null 2>&1
 
sgdisk -Z ${NEWDISK}
sgdisk -R ${NEWDISK} ${GOODDISK} -G
partprobe ${NEWDISK}
 
# Only if we have UEFI
if [ "ZZ${UEFI}" = "ZZy" ]; then
    sgdisk -c${PARTITION_EFI}:"EFI_${NEW}" ${NEWDISK}
fi
 
# Encrypted means /boot on its own zfs pool, and rsvd is raided
if [ "ZZ${LUKS}" = "ZZy" ]; then
    sgdisk -c${PARTITION_BOOT}:"BOOT_${NEW}" ${NEWDISK}
fi
 
# Only if swap partition
if [ ${SIZE_SWAP} ] &&[ ${SIZE_SWAP} != 0 ]; then
    sgdisk -c${PARTITION_SWAP}:"SWAP_${NEW}" ${NEWDISK}
fi
 
# Always have these
sgdisk -c${PARTITION_GRUB}:"GRUB_${NEW}" ${NEWDISK}
sgdisk -c${PARTITION_RSVD}:"RSVD_${NEW}" ${NEWDISK}
sgdisk -c${PARTITION_DATA}:"ZFS_${NEW}" ${NEWDISK}
partprobe ${NEWDISK}
 
if [ "ZZ${LUKS}" = "ZZy" ]; then
    if [ ${#DISKS[@]} -gt 1 ]; then
        mdadm --manage /dev/md/${BOXNAME}:rsvd --add ${NEWDISK}${PARTITION_RSVD}
    fi
fi
if [ ${SIZE_SWAP} ] &&[ ${SIZE_SWAP} != 0 ]; then
    if [ ${#DISKS[@]} -gt 1 ]; then
        mdadm --manage /dev/md/${BOXNAME}:swap --add ${NEWDISK}${PARTITION_SWAP}
    fi
fi
 
mkfs.vfat -v -F32 -s2 -n "EFI_${NEW}" ${NEWDISK}${PARTITION_EFI}
 
if [ "ZZ${LUKS}" = "ZZy" ]; then
    # Get failed zpool partitions and new encrypted partitions
    OLD${POOLNAME}="/dev/mapper/`zpool status -v ${POOLNAME} | fgrep FAULTED | tr -s ' ' | cut -d' ' -f2`"
    NEW${POOLNAME}=/dev/mapper/root_crypt${NEW}
   
    OLDBOOT="/dev/mapper/`zpool status -v boot | fgrep FAULTED | tr -s ' ' | cut -d' ' -f2`"
    NEWBOOT="${NEWDISK}${PARTITION_BOOT}"
    ln -sf ${NEWDISK}${PARTITION_BOOT} /dev
 
    # Replace boot pool (only used with LUKS, non-encrypted though)
    zpool replace boot ${OLDBOOT} ${NEWBOOT}
 
    # Create new root_crypt${NEW}, add derived key to it
    echo ${PASSPHRASE} | cryptsetup --batch-mode luksFormat -c aes-xts-plain64 -s 512 -h sha512 ${NEWDISK}${PARTITION_DATA}
    echo ${PASSPHRASE} | cryptsetup luksOpen ${NEWDISK}${PARTITION_DATA} root_crypt${NEW}
    ln -sf /dev/mapper/root_crypt${NEW} /dev/root_crypt${NEW}
    /lib/cryptsetup/scripts/decrypt_derived ${BOXNAME}:rsvd > /tmp/key
    echo ${PASSPHRASE} | cryptsetup luksAddKey ${NEWDISK}${PARTITION_DATA} /tmp/key
 
    # Recreate crypttab
    # Remove old disk
    cp /etc/crypttab /etc/crypttab.backup
    cat /etc/crypttab.backup | fgrep -v `basename ${OLD${POOLNAME}}` > /etc/crypttab
 
    # Add new disk
    echo "root_crypt${NEW}  UUID=$(blkid ${NEWDISK}${PARTITION_DATA} -s UUID -o value) none    luks,discard,noauto,checkargs=${BOXNAME}:swap,keyscript=/lib/cryptsetup/scripts/decrypt_derived" >> /etc/crypttab
 
    # Recreate cryptroot
    # Remove old disk
    cp /etc/initramfs-tools/conf.d/cryptroot /etc/initramfs-tools/conf.d/cryptroot.backup
    cat /etc/initramfs-tools/conf.d/cryptroot.backup | fgrep -v `basename ${OLD${POOLNAME}}` > /etc/initramfs-tools/conf.d/cryptroot
 
    # Add new disk
    echo "target=root_crypt${NEW},source=UUID=$(blkid ${NEWDISK}${PARTITION_DATA} -s UUID -o value),rootdev,keyscript=/scripts/luks/get.root_crypt.decrypt_derived" >> /etc/initramfs-tools/conf.d/cryptroot
else
    # Replace failed zpool drive/partition with new drive/partition
    OLD${POOLNAME}="/`zpool status -v ${POOLNAME} | fgrep was | cut -d'/' -f2-`"
    # NEW${POOLNAME}="`ls -al /dev/disk/by-id | fgrep ${NEWDISK}${PARTITION_DATA} | sed -e 's/.*\(ata.*\) ->.*/\1/'`"
    NEW${POOLNAME}="${NEWDISK}${PARTITION_DATA}"
    ln -sf ${NEWDISK}${PARTITION_DATA} /dev
fi
 
# Recreate fstab /boot/efi entries
# Add new disk
if [ "ZZ${UEFI}" = "ZZy" ]; then
    mkdir -p /boot/efi_${NEW}
    echo "UUID=$(blkid -t LABEL=EFI_${NEW} -s UUID -o value) /boot/efi_${NEW} vfat defaults,nobootwait,nofail 0 0" >>/etc/fstab
    mount /boot/efi_${NEW}
 
    # Copy EFI stuff from good disk to new disk (/boot/efi_${NEW})
    cp -a `cat /etc/fstab | fgrep "\`blkid ${GOODDISK}${PARTITION_EFI} -s UUID -o value\`" | cut -d' ' -f2`/* /boot/efi_${NEW}
 
    # Remove old /boot/efi_ (not mounted because ... disk is gone) dir from fstab
    OLDEFI=`( mount | fgrep /boot/efi_ | cut -d' ' -f3 ; fgrep /boot/efi_ /etc/fstab | cut -d' ' -f2 ) | sort | uniq -u`
    umount -f ${OLDEFI}
    rm -rf ${OLDEFI}
    cp /etc/fstab /etc/fstab.backup
    cat /etc/fstab.backup | fgrep -v ${OLDEFI} > /etc/fstab
fi
 
zpool replace ${POOLNAME} ${OLD${POOLNAME}} ${NEW${POOLNAME}}
zpool status -v
 
# Tell initramfs about new cryptroot etc
update-initramfs -c -k all
__EOFREPLACE2__
chmod +x /mnt/zfs/root/Replace-failed-drive.sh
# ============= Replacing drive helper script ====================================================
 
# ============= Reboot testing helper script =====================================================
# This goes in build-system to allow easy entry/exit from chroot new system in /mnt/zfs
cat > /root/Reboot-testing.sh << __EOFSETUP__
#!/bin/bash
 
# This script is to help with testing the newly installed zfs-on-root(-on luks maybe) system
# Invoked as Reboot-testing.sh will simply import the zpool (after possibly opening luks devices)
# bind-mount dev/sys/proc and start a new shell for you to work in.  Exit that shell and it
# unmounts the bind-mounts and exports the zpool
 
# Invoked with -y does the same but actually chroots into the mounted system in /mnt/zfs
 
export BOXNAME=${BOXNAME}
export POOLNAME=${POOLNAME}
export LUKS=${LUKS}
export DETACHEDHEADERS=${DETACHEDHEADERS}
export PASSPHRASE=${PASSPHRASE}
export UEFI=${UEFI}
export USERNAME=${USERNAME}
export UPASSWORD=${UPASSWORD}
export SSHPUBKEY="${SSHPUBKEY}"
export GITPUBKEYS="${GITPUBKEYS}"
export SIZE_SWAP=${SIZE_SWAP}
export SWAPDEVRAW=${SWAPDEVRAW}
export RSVDDEVRAW=${RSVDDEVRAW}
export PARTITION_EFI=${PARTITION_EFI}
export PARTITION_GRUB=${PARTITION_GRUB}
export PARTITION_BOOT=${PARTITION_BOOT}
export PARTITION_SWAP=${PARTITION_SWAP}
export PARTITION_DATA=${PARTITION_DATA}
export PARTITION_RSVD=${PARTITION_RSVD}
 
__EOFSETUP__
 
for DISK in `seq 1 ${#DISKS[@]}` ; do
    echo "DISKS[${DISK}]=${DISKS[${DISK}]}" >> /root/Reboot-testing.sh
done
 
cat >> /root/Reboot-testing.sh << '__EOFREBOOT__'
 
# If this is an encrypted system ...
if [ "ZZ${LUKS}" = "ZZy" ]; then
    ######## Detached headers
    # RSVD - LUKS-header-${BOXNAME}:rsvd.luksheader
    # SWAP - LUKS-header-${BOXNAME}:swap.luksheader
    # ROOT - LUKS-header-${DISKS[${DISK}]}${PARTITION_DATA}.luksheader
 
    if [ ${SIZE_SWAP} ] &&[ ${SIZE_SWAP} != 0 ]; then
        if [ ${#DISKS[@]} -gt 1 ]; then
            if [ "ZZ${DETACHEDHEADERS}" = "ZZy" ]; then
                echo ${PASSPHRASE} | cryptsetup luksOpen /dev/md/${BOXNAME}:swap --header /root/headers/LUKS-header-${BOXNAME}:swap.luksheader ${BOXNAME}:swap
            else
                echo ${PASSPHRASE} | cryptsetup luksOpen /dev/md/${BOXNAME}:swap ${BOXNAME}:swap
            fi
            ln -sf /dev/mapper/${BOXNAME}:swap /dev
        fi
    fi
 
    # Unlock the ZFS safety partition
    if [ "ZZ${DETACHEDHEADERS}" = "ZZy" ]; then
        echo ${PASSPHRASE} | cryptsetup luksOpen ${RSVDDEVRAW} --header /root/headers/LUKS-header-${BOXNAME}:rsvd.luksheader ${BOXNAME}:rsvd
    else
        echo ${PASSPHRASE} | cryptsetup luksOpen ${RSVDDEVRAW} ${BOXNAME}:rsvd
    fi
    ln -sf /dev/mapper/${BOXNAME}:rsvd /dev
 
    # Unlock each ZFS partition
    for DISK in `seq 1 ${#DISKS[@]}` ; do
        if [ "ZZ${DETACHEDHEADERS}" = "ZZy" ]; then
            echo ${PASSPHRASE} | cryptsetup luksOpen ${DISKS[${DISK}]}${PARTITION_DATA} --header /root/headers/LUKS-header-${DISKS[${DISK}]}${PARTITION_DATA}.luksheader root_crypt${DISK}
        else
            echo ${PASSPHRASE} | cryptsetup luksOpen ${DISKS[${DISK}]}${PARTITION_DATA} root_crypt${DISK}
        fi
        ln -sf /dev/mapper/root_crypt${DISK} /dev/root_crypt${DISK}
 
        # /boot partition is NOT encrypted, so use by-id
        ln -sf ${DISKS[${DISK}]}${PARTITION_BOOT} /dev
    done
   
    # Import the encrypted pool
    zpool import -N -f -d /dev/mapper -R /mnt/zfs ${POOLNAME}
else  # Not LUKS
    # Just create links for the encrypted partitions in /dev
    for DISK in `seq 1 ${#DISKS[@]}` ; do
        ln -sf ${DISKS[${DISK}]}${PARTITION_DATA} /dev
    done
   
    # Import the unencrypted pool
    zpool import -N -f -d /dev/disk/by-id -R /mnt/zfs ${POOLNAME}
fi # LUKS
 
# Mount the root dataset, THEN mount the rest of the datasets (which live on root, duh)
zfs mount ${POOLNAME}/ROOT/ubuntu
zfs mount -a
 
# Only have a boot pool if the rest was encrypted
if [ "ZZ${LUKS}" = "ZZy" ]; then
    rm -rf /mnt/zfs/boot/grub
    zpool import -f -d /dev/disk/by-id -R /mnt/zfs boot
fi
 
# Mount EFI partitions
if [ "ZZ${UEFI}" = "ZZy" ]; then
    # fgrep efi_ /mnt/zfs/etc/fstab | cut -d' ' -f1-2 | sed -e 's!/boot!/mnt/zfs/boot!; s/UUID=/-U /' | xargs -L1 mount
    mount /dev/md/${BOXNAME}:efi /mnt/zfs/boot/efi
fi
 
# Mount the supporting virtual filesystems
[ ! -e /mnt/zfs/etc/mtab ] && ln -s /proc/mounts /mnt/zfs/etc/mtab
mount -o bind /proc /mnt/zfs/proc
mount -o bind /dev /mnt/zfs/dev
mount -o bind /dev/pts /mnt/zfs/dev/pts
mount -o bind /sys /mnt/zfs/sys
 
# Only chroot if we passed -y into script, otherwise just start a new shell
if [ "$1" = "-y" ]; then
    chroot /mnt/zfs /bin/bash --login
else
    bash --login
fi
 
# OK, exited chroot (or shell) so unmount the virtual filesystems
[ "ZZ${UEFI}" = "ZZy" ] && umount /mnt/zfs/boot/efi
umount /mnt/zfs/sys
umount /mnt/zfs/dev/pts
umount /mnt/zfs/proc
umount /mnt/zfs/dev
 
# Export the pools again so they will cleanly import on reboot
if [ "ZZ${LUKS}" = "ZZy" ]; then
    zpool export boot
fi
zpool export ${POOLNAME}
 
# If system is encrypted need to cleanly close the LUKS devices
if [ "ZZ${LUKS}" = "ZZy" ]; then
    if [ ${SIZE_SWAP} ] &&[ ${SIZE_SWAP} != 0 ]; then
        cryptsetup luksClose ${BOXNAME}:swap
    fi
    cryptsetup luksClose ${BOXNAME}:rsvd
    for DISK in `seq 1 ${#DISKS[@]}` ; do
        cryptsetup luksClose root_crypt${DISK}
    done
fi # LUKS
__EOFREBOOT__
chmod +x /root/Reboot-testing.sh
# ============= END Reboot testing helper script =====================================================
 
# Snapshot the clean debootstrap install
zfs snap ${POOLNAME}/ROOT/ubuntu@debootstrap
if [ "ZZ${LUKS}" = "ZZy" ]; then
    zfs snap boot/ubuntu@debootstrap
fi
 
# Bind mount and chroot into new system
[ ! -e /mnt/zfs/etc/hostid ] && hostid > /mnt/zfs/etc/hostid
[ ! -e /mnt/zfs/etc/mtab ] && ln -s /proc/mounts /mnt/zfs/etc/mtab
mount -o bind /proc /mnt/zfs/proc
mount -o bind /dev /mnt/zfs/dev
mount -o bind /dev/pts /mnt/zfs/dev/pts
mount -o bind /sys /mnt/zfs/sys
 
# chroot into new system and run Setup.sh
chroot /mnt/zfs /bin/bash --login -c /root/Setup.sh
# After exit from Setup.sh in chroot continue from here
 
# Grab the Setup.log from the installed system
cp /mnt/zfs/root/Setup.log .
 
# Also put the Reboot-testing.sh script into the new root, for reference
cp Reboot-testing.sh /mnt/zfs/root
 
[ "ZZ${UEFI}" = "ZZy" ] && umount /mnt/zfs/boot/efi
umount /mnt/zfs/sys
umount /mnt/zfs/dev/pts
umount /mnt/zfs/proc
umount /mnt/zfs/dev
 
if [ "ZZ${LUKS}" = "ZZy" ]; then
    echo "# ***************************************************************************************"
    echo "#"
    echo "#  Do not forget to save (and encrypt) the LUKS header backup files"
    echo "#"
    for LUKSBACKUP in headers/LUKS-header-backup* ; do
        echo "#  ${LUKSBACKUP}"
        cp ${LUKSBACKUP} /mnt/zfs/root/headers
    done
    chmod -R 700 /mnt/zfs/root/headers
    echo "#"
    echo "# ***************************************************************************************"
 
    zpool export boot
fi
zpool export ${POOLNAME}
 
exit
