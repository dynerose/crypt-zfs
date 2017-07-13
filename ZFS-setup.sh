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
