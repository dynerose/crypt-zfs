# Basic use from ubuntu-14.04.4-desktop-amd64.iso Live-CD
#
# Boot ISO, select "Try Ubuntu"
# Open terminal
# sudo -i
# wget http://<link> -O ZFS-setup.sh
# chmod +x ZFS-setup.sh
# nano ZFS-setup.sh
#    set variables in ZFS-setup.sh - see below
# ./ZFS-setup.sh
#    ctrl-C to exit at list of disks
# nano ZFS-setup.disks.txt
#    Ensure list of disks is correct
# ./ZFS-setup.sh
#    press <enter> to accept list of disks and swap size
#    enter password for main userid
#    enter password again
#!/bin/bash

# ZFS-setup.sh          2016-03-24 19:42

# Auto-installer for clean new system using root on zfs, and optionally on
# luks encrypted disks.  It installs Ubuntu 14.04.04 or 16.04 with everything
# needed to support ZFS and potentially LUKS.  Without LUKS everything lives
# in the main rpool pool.  With LUKS then /boot lives in its own boot pool.
# Grub2 is installed to all disks, so the system can boot cleanly from *any*
# disk, even with a failed disk.

# This script is meant to be run from an Ubuntu live-CD or a minimal
# install (from a usb key for example).  It will create a list of all disks it
# can see then ask the user to edit that list if required.  All disks listed
# in that ZFS-setup.disks.txt file will be wiped CLEAN for the install.

# It can copy the /etc/ssh directory from the build-host into the newly
# created system.  Makes for *much* easier testing when running multiple times.

# Basic use from ubuntu-14.04.4-desktop-amd64.iso Live-CD
#
# Boot ISO, select "Try Ubuntu"
# Open terminal
# sudo -i
# wget http://<link> -O ZFS-setup.sh
# chmod +x ZFS-setup.sh
# nano ZFS-setup.sh
#    set variables in ZFS-setup.sh - see below
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

# Setup.sh                                      : Goes in /root of the new system, and is used to build/install
#                                                       : the rest of the system after debootstrap.
# Reboot-testing.sh                     : Goes in the local build-host /root, and is used for
#                                                       : entering/exiting the new system via chroot for debugging.
# Replace-failed-drive.sh       : Goes in /root of new system, used to replace a failed drive.
#                                                       : NOTE - incomplete

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
# /etc/initramfs-tools/conf.d/cryptroot                             (if using LUKS)
# /etc/initramfs-tools/conf.d/dropbear_network                      (if using LUKS)
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
#       So /etc/initramfs-tools/scripts/init-premount/network-down must be customized, or we

#       must put net.ifnames=0 on the grub cmdline to use old eth0 style network names rather
#       than the newer enp3s0 type.  Search below for GRUB_CMDLINE_LINUX_DEFAULT


# -------Set the following variables ---------------------------------------------------------------

# Which version of Ubuntu to install trusty=14.04 xenial=16.04
SUITE=zesty

# Userid to create in new system
USERNAME=sa

# SSH pubkey to add to new system
SSHPUBKEY="ssh-rsa ABCDE= Johnny Bravo"

# System name (also used for mdadm raid set names and filesystem LABELs)
# Note: Only first 10 chars of name will be used for LABELs
SYSNAME=instzfs

# Using LUKS for encryption ? Please use a nice long complicated passphrase (y/n)
# If enabled, will encrypt partition_swap (md raid) and partition_data (zfs)
LUKS=y
PASSPHRASE=sa

# Zero/randomize out the disks for LUKS ?  (y/n)
ZERO=

# Using a proxy like apt-cacher-ng ?
# PROXY=

# zpool raid level to use for more than 2 disks - raidz, raidz2, raidz3, mirror
# For 2 disks, will be forced to mirror
ZPOOLEVEL=mirror

# Copy the build-host /etc/ssh into the newly created system ?
COPY_SSH=y

# Are we configuring to use UEFI ?
UEFI=n

# Force the swap partition size for each disk in MB if you don't want it calculated
# If you want Resume to work, total swap must be > total ram
# Set to 0 to disable (SIZE_SWAP = swap partitions, SIZE_ZVOL = zfs zvol in rpool)
SIZE_SWAP=0
SIZE_ZVOL=32768

# Use zswap compressed page cache in front of swap ? https://wiki.archlinux.org/index.php/Zswap
USE_ZSWAP="\"zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=25\""

# USE_ZSWAP=

# Set the source of debootstrap - can be a local repo built with apt-move
DEBOOTSTRAP="http://us.archive.ubuntu.com/ubuntu/"
# DEBOOTSTRAP="file:///root/UBUNTU"

# Generic partition setup as follows
# sdX1 :        EFI boot
# sdX2 :        Grub boot
# sdX3 :        /boot (only used for LUKS)
# sdX4 :        swap
# sdX5 :        main ZFS partition
# sdX9 :        ZFS reserved

# Partition numbers and sizes of each partition in MB
PARTITION_EFI=1
SIZE_EFI=100
PARTITION_GRUB=2
SIZE_GRUB=2
PARTITION_BOOT=3
SIZE_BOOT=500
PARTITION_SWAP=4
PARTITION_DATA=5
PARTITION_RSVD=9

# ------ End of user settable variables ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

BOXNAME=${SYSNAME:0:10}
if [ ${#SYSNAME} -gt 10 ]; then
        echo "$(tput setaf 1)!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!$(tput sgr0)"
        echo "$(tput setaf 1)!!$(tput sgr0)"
        echo "$(tput setaf 1)!!$(tput setaf 6) ${SYSNAME}$(tput sgr0) is too long - must be 10 chars max"
        echo "$(tput setaf 1)!!$(tput sgr0) Will use $(tput setaf 6)${BOXNAME}$(tput sgr0) in labels"
        echo "$(tput setaf 1)!!$(tput sgr0)"
        echo "$(tput setaf 1)!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!$(tput sgr0)"
        echo "$(tput setaf 3) Press <enter> to continue, or ctrl-C to abort $(tput setaf 1)"
        read QUIT
        echo ""
fi

# Generate (if necessary) list of disks and ask user below if it's good to go
[ ! -e /root/ZFS-setup.disks.txt ] && for disk in `ls -l /dev/disk/by-id | egrep -v '(-part|md-|dm-)' | sort -t '/' -k3 | tr -s " " | cut -d' ' -f9`; do echo $disk >> /root/ZFS-setup.disks.txt; done

i=1
for disk in `cat /root/ZFS-setup.disks.txt` ; do
    DISKS[$i]=$disk
    i=$(($i+1))
done
# Calculate proper SWAP size (if not defined above) - should be same size as total RAM in system
MEMTOTAL=`cat /proc/meminfo | fgrep MemTotal | tr -s ' ' | cut -d' ' -f2`
[ ${SIZE_SWAP} ] || SIZE_SWAP=$(( ${MEMTOTAL} / ${#DISKS[@]} / 1024 ))

echo "$(tput setaf 1)!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "$(tput setaf 1)!!"
echo "$(tput setaf 1)!!$(tput sgr0)  These are the disks we're about for $(tput setaf 1)FORMAT$(tput sgr0) for ZFS"
echo "$(tput setaf 1)!!"
i=1
for disk in `seq 1 ${#DISKS[@]}` ; do
    echo "$(tput setaf 1)!!$(tput sgr0)  disk $i = ${DISKS[$i]} (`readlink /dev/disk/by-id/${DISKS[$i]} | cut -d/ -f3`)"
    i=$(($i+1))
done
echo "$(tput setaf 1)!!"
echo "$(tput setaf 1)!!$(tput sgr0)  Be $(tput setaf 1)SURE$(tput sgr0), really $(tput setaf 1)SURE$(tput sgr0), as they will be wiped completely"
echo "$(tput setaf 1)!!$(tput sgr0)  Otherwise abort and edit the $(tput setaf 6)/root/ZFS-setup.disks.txt$(tput sgr0) file"
echo "$(tput setaf 1)!!"

if [ ${SIZE_SWAP} != 0 ]; then
        if [ ${#DISKS[@]} -gt 2 ]; then
                # raid10 size
                SIZE_SWAP_TOTAL=$(( ${SIZE_SWAP} * ${#DISKS[@]} / 2 ))
        else
                # raid1 mirror size
                SIZE_SWAP_TOTAL=$(( ${SIZE_SWAP} * ${#DISKS[@]} ))
        fi
        echo "$(tput setaf 1)!!$(tput sgr0)  ${#DISKS[@]} SWAP partitions of ${SIZE_SWAP}MB = $(( ${SIZE_SWAP_TOTAL} / 1024 ))GB = ${SIZE_SWAP_TOTAL}MB total"
        echo -n "$(tput setaf 1)!!$(tput sgr0)  Ram = ${MEMTOTAL}kb Swap partitions $(tput setaf 3)"
        if [ ${#DISKS[@]} -gt 2 ]; then
                echo -n "raid10"
        else
                echo -n "raid1"
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

echo "$(tput setaf 1)!!!!!!!!$(tput setaf 3) Press <enter> to continue, or ctrl-C to abort $(tput setaf 1)!!!!!!!!!!!!!!!!!!!!!"
read QUIT
# Input USERNAME password for main id
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

# Make sure we have utilities we need
if [ ! -e /sbin/zpool ]; then
        apt-add-repository --yes ppa:zfs-native/stable
        echo "--- apt-get update"
        apt-get update > /dev/null
        apt-get -y --no-install-recommends install ubuntu-zfs
fi
modprobe zfs

for UTIL in /sbin/{mdadm,gdisk,cryptsetup} /usr/sbin/debootstrap ; do
        [ ! -e ${UTIL} ] && apt-get -y --no-install-recommends install `basename ${UTIL}`
done
# For more packages whose name doesn't match the executable, use this method
#
# UTIL_FILE[0]=/sbin/mdadm ;                    UTIL_PKG[0]=mdadm
# UTIL_FILE[1]=/sbin/gdisk ;                    UTIL_PKG[1]=gdisk
# UTIL_FILE[3]=/usr/sbin/debootstrap ;  UTIL_PKG[2]=debootstrap
# UTIL_FILE[4]=/usr/sbin/sshd ;                 UTIL_PKG[4]=openssh-server
# for UTIL in `seq 0 ${#UTIL_FILE[@]}` ; do
#       UTIL_INSTALL="${UTIL_INSTALL} ${UTIL_PKG[${UTIL}]}"
# done
# apt-get -y --no-install-recommends install ${UTIL_INSTALL}

# Unmount any mdadm disks that might have been automounted
umount /dev/md* > /dev/null 2>&1

# Stop all found mdadm arrays
mdadm --stop --force /dev/md* > /dev/null 2>&1

# Zero entire disk if requested
if [ "ZZ${ZERO}" = "ZZy" ]; then
        echo "-----------------------------------------------------------------------------"
        echo "Fetching frandom kernel module"
        # urandom is limited, so use frandom module
        [ ! -e /var/lib/dpkg/info/build-essential.list ] && apt-get -y install build-essential
        mkdir -p /usr/src/frandom
        wget --no-proxy http://billauer.co.il/download/frandom-1.1.tar.gz -O /usr/src/frandom/frandom-1.1.tar.gz
        cd /usr/src/frandom
        tar xvzf frandom-1.1.tar.gz
        cd frandom-1.1
        make
        install -m 644 frandom.ko /lib/modules/`uname -r`/kernel/drivers/char/
        depmod -a
        modprobe frandom

        for DISK in `seq 1 ${#DISKS[@]}` ; do
                echo "Zeroing ${DISKS[${DISK}]}"
                dd if=/dev/frandom of=/dev/disk/by-id/${DISKS[${DISK}]} bs=512 count=$(blockdev --getsz /dev/disk/by-id/${DISKS[${DISK}]}) &
                WAITPIDS="${WAITPIDS} "$!
        done

        # USR1 dumps status of dd, this will take around 6 hours for 3TB SATA disk
        # killall -USR1 dd

        echo "Waiting for disk zeroing to finish"
        wait ${WAITPIDS}
fi

echo "-----------------------------------------------------------------------------"
echo "Clearing out md raid, zpool and LUKS info from disks"
for DISK in `seq 1 ${#DISKS[@]}` ; do
for DISK in `seq 1 ${#DISKS[@]}` ; do
        echo ">>>>> ${DISKS[${DISK}]}"

        # wipe it out ...
        wipefs -a /dev/disk/by-id/${DISKS[${DISK}]}

        # Clear any old zpool info
        zpool labelclear -f /dev/disk/by-id/${DISKS[${DISK}]} > /dev/null 2>&1 [ -e /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA} ] && zpool labelclear -f /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA} > /dev/null 2>&1

        # Wipe mdadm superblock from all partitions found, even if not md raid partition
        mdadm --zero-superblock --force /dev/disk/by-id/${DISKS[${DISK}]} > /dev/null 2>&1 
        [ -e /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_BOOT} ] && mdadm --zero-superblock --force /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_BOOT} > /dev/null 2>&1 
        [ -e /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_SWAP} ] && mdadm --zero-superblock --force /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_SWAP} > /dev/null 2>&1
        [ -e /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_RSVD} ] && mdadm --zero-superblock --force /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_RSVD} > /dev/null 2>&1

        # Clear any old LUKS or mdadm info
        [ -e /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA} ] && dd if=/dev/zero of=/dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA} bs=512 count=20480 > /dev/null 2>&1
        [ -e /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_SWAP} ] && dd if=/dev/zero of=/dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_SWAP} bs=512 count=20480 > /dev/null 2>&1
        [ -e /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_RSVD} ] && dd if=/dev/zero of=/dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_RSVD} bs=512 count=4096 > /dev/null 2>&1

        # Zero old MBR and GPT partition information on disks
        sgdisk -Z /dev/disk/by-id/${DISKS[${DISK}]}
        # Create new GPT partition label on disks
        parted -s -a optimal /dev/disk/by-id/${DISKS[${DISK}]} mklabel gpt
        # Rescan partitions
        partprobe /dev/disk/by-id/${DISKS[${DISK}]}
 if [ "ZZ${UEFI}" = "ZZy" ]; then
                sgdisk -n1:2048:+256M       -t1:EF00 -c1:"EFI_${DISK}"  /dev/disk/by-id/${DISKS[${DISK}]}
        fi
                sgdisk -n2:0:+5M            -t2:EF02 -c2:"GRUB_${DISK}" /dev/disk/by-id/${DISKS[${DISK}]}
        if [ "ZZ${LUKS}" = "ZZy" ]; then
                sgdisk -n3:0:+${SIZE_BOOT}M -t3:FD00 -c3:"BOOT_${DISK}" /dev/disk/by-id/${DISKS[${DISK}]}
        fi
        if [ ${SIZE_SWAP} != 0 ]; then
                sgdisk -n4:0:+${SIZE_SWAP}M -t4:FD00 -c4:"SWAP_${DISK}" /dev/disk/by-id/${DISKS[${DISK}]}
        fi
                sgdisk -n5:0:-8M            -t5:BF01 -c5:"ZFS_${DISK}"  /dev/disk/by-id/${DISKS[${DISK}]}
                sgdisk -n9:0:0              -t9:BF07 -c9:"RSVD_${DISK}" /dev/disk/by-id/${DISKS[${DISK}]}
        partprobe /dev/disk/by-id/${DISKS[${DISK}]}
        echo ""
done
gdisk -l /dev/disk/by-id/${DISKS[1]}

# And, just to be sure, since sometimes stuff hangs around
# Unmount any mdadm disks that might have been automounted
umount /dev/md* > /dev/null 2>&1

# Stop all found mdadm arrays
mdadm --stop --force /dev/md* > /dev/null 2>&1

# Build list of partitions to use for ...
# Boot partition (mirror across all disks)
PARTSBOOT=

PARTSSWAP=
PARTSRSVD=
# ZFS partitions to create zpool with
ZPOOLDISK=
for DISK in `seq 1 ${#DISKS[@]}` ; do
        PARTSSWAP="${PARTSSWAP} /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_SWAP}"
        PARTSBOOT="${PARTSBOOT} /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_BOOT}"
        if [ "ZZ${LUKS}" = "ZZy" ]; then
                PARTSRSVD="${PARTSRSVD} /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_RSVD}"
                ZPOOLDISK="${ZPOOLDISK} /dev/mapper/root_crypt${DISK}"
        else
                ZPOOLDISK="${ZPOOLDISK} /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA}"
        fi
done

# Pick raid level to use dependent on number of disks
# disks = 2 : zpool and swap use mirror
# disks > 2 : zpool use raidz, swap use raid10
if [ ${#DISKS[@]} = 2 ]; then
        ZPOOLEVEL=mirror
        SWAPRAID=raid1
else
        # ZPOOLEVEL is left to whatever you chose at top vars list
        SWAPRAID="raid10 -p f2"
fi

echo "-----------------------------------------------------------------------------"
# Create raid for swap if SIZE_SWAP defined (use -p f2 for raid10)
if [ ${SIZE_SWAP} != 0 ]; then
        echo "Creating ${BOXNAME}:swap raid0 for new system"
        echo y | mdadm --create /dev/md/${BOXNAME}:swap --metadata=1.0 --force --level=${SWAPRAID} --raid-device=${#DISKS[@]} --homehost=${BOXNAME} --name=swap --assume-clean ${PARTSSWAP}
fi

# Format EFI System Partitions on both disks as FAT32
if [ "ZZ${UEFI}" = "ZZy" ]; then
        echo "Formatting EFI system partitions"
        for DISK in `seq 1 ${#DISKS[@]}` ; do
                echo "${DISKS[${DISK}]}-part${PARTITION_EFI}"
                mkfs.vfat -v -F32 -s2 -n "EFI_${DISK}" /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_EFI} > /dev/null 2>&1
        done
fi

# Create LUKS devices if LUKS enabled
if [ "ZZ${LUKS}" = "ZZy" ]; then
        echo "-----------------------------------------------------------------------------"
        if [ ${SIZE_SWAP} != 0 ]; then
                # Create encrypted swap on top of md raid array
                echo "Encrypting SWAP ${BOXNAME}:swap"
                echo ${PASSPHRASE} | cryptsetup --batch-mode luksFormat -c aes-xts-plain64 -s 512 -h sha512 /dev/md/${BOXNAME}:swap
                echo ${PASSPHRASE} | cryptsetup luksOpen /dev/md/${BOXNAME}:swap ${BOXNAME}:swap
                ln -sf /dev/mapper/${BOXNAME}:swap /dev/${BOXNAME}:swap
        fi

        # Create encrypted rsvd on top of md array - used as main key for other encrypted
        echo "Creating ${BOXNAME}:rsvd raid0 for new system"
        echo y | mdadm --create /dev/md/${BOXNAME}:rsvd --metadata=1.0 --force --level=raid1 --raid-device=${#DISKS[@]} --homehost=${BOXNAME} --name=rsvd ${PARTSRSVD}
        echo ${PASSPHRASE} | cryptsetup --batch-mode luksFormat -c aes-xts-plain64 -s 512 -h sha512 /dev/md/${BOXNAME}:rsvd
        echo ${PASSPHRASE} | cryptsetup luksOpen /dev/md/${BOXNAME}:rsvd ${BOXNAME}:rsvd
        ln -sf /dev/mapper/${BOXNAME}:rsvd /dev

        # Get derived key and insert into other encrypted devices
        /lib/cryptsetup/scripts/decrypt_derived ${BOXNAME}:rsvd > /tmp/key
        if [ ${SIZE_SWAP} != 0 ]; then
                echo ${PASSPHRASE} | cryptsetup luksAddKey /dev/md/${BOXNAME}:swap /tmp/key
        fi

        # Create encrypted ZFS source partitions
        for DISK in `seq 1 ${#DISKS[@]}` ; do
                echo "Encrypting ZFS partition ${DISKS[${DISK}]}-part${PARTITION_DATA}"
                echo ${PASSPHRASE} | cryptsetup --batch-mode luksFormat -c aes-xts-plain64 -s 512 -h sha512 /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA}
                echo ${PASSPHRASE} | cryptsetup luksOpen /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA} root_crypt${DISK}
                ln -sf /dev/mapper/root_crypt${DISK} /dev/root_crypt${DISK}

                # Insert derived key
                echo ${PASSPHRASE} | cryptsetup luksAddKey /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA} /tmp/key

                # Backup LUKS headers for ZFS partitions
                cryptsetup luksHeaderBackup /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA}--header-backup-file /root/LUKS-header-backup-${DISKS[${DISK}]}-part${PARTITION_DATA}.img
                        done
fi # LUKS

# Really, REALLY ugly hack to accomodate update-grub
for DISK in `seq 1 ${#DISKS[@]}` ; do
        # Only create DATA partition link if *not* using LUKS
        [ "ZZ${LUKS}" = "ZZ" ] && ln -sf /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA} /dev
        ln -sf /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_BOOT} /dev
done

echo "-----------------------------------------------------------------------------"
if [ "ZZ${LUKS}" = "ZZy" ]; then
        echo "Creating /boot ZFS raidz/mirror for new system"
        # For creating a /boot pool use -o version=28

        #zpool create -f -o ashift=12 -o cachefile= -o version=28 \
        #       -O atime=off -O canmount=off -O compression=zle -m none \
        #       boot ${ZPOOLEVEL} ${PARTSBOOT}
        zpool create -f -o ashift=12 -m none \
      -d \
      -o feature@async_destroy=enabled \
      -o feature@empty_bpobj=enabled \
      -o feature@lz4_compress=enabled \
      -o feature@spacemap_histogram=enabled \
      -o feature@enabled_txg=enabled \
      -O atime=off -O canmount=off -O compression=lz4 \
      boot ${ZPOOLEVEL} ${PARTSBOOT}

        zfs set com.sun:auto-snapshot=false boot
        zpool export boot
fi # LUKS
# Create main zpool
zpool create -f -o ashift=12 \
      -d \
      -o feature@async_destroy=enabled \
      -o feature@empty_bpobj=enabled \
      -o feature@lz4_compress=enabled \
      -o feature@spacemap_histogram=enabled \
      -o feature@enabled_txg=enabled \
      -O atime=off -O canmount=off -O compression=lz4 \
      rpool ${ZPOOLEVEL} ${ZPOOLDISK}
zfs set mountpoint=/ rpool

# Mount rpool under /mnt/zfs to install system, clean /mnt/zfs first
zpool export rpool
rm -rf /mnt/zfs
if [ "ZZ${LUKS}" = "ZZy" ]; then
        zpool import -d /dev/mapper -R /mnt/zfs rpool
else
        zpool import -d /dev/disk/by-id -R /mnt/zfs rpool
fi

# No need to auto-snapshot the pool itself, though you have to explicitly set true for datasets
zfs set com.sun:auto-snapshot=false rpool

# Create container for root dataset
zfs create -o canmount=off -o mountpoint=none -o compression=lz4 -o atime=off rpool/ROOT

# Enable auto snapshots with zfs-auto-snapshot
zfs set com.sun:auto-snapshot=true rpool/ROOT
# Set threshold for zfs-auto-snapshot
zfs set com.sun:snapshot-threshold=2000000 rpool/ROOT

# Create root dataset to hold main filesystem
zfs create -o canmount=noauto -o mountpoint=/ -o compression=lz4 -o atime=off -o xattr=sa rpool/ROOT/ubuntu
zpool set bootfs=rpool/ROOT/ubuntu rpool
zfs mount rpool/ROOT/ubuntu

if [ "ZZ${LUKS}" = "ZZy" ]; then
        zpool import -d /dev/disk/by-id -R /mnt/zfs boot
        # Set up /boot filesystem and possibly for EFI
        # Create container for boot dataset
        ### zfs create -o canmount=off -o mountpoint=none -o compression=zle -o atime=off boot/BOOT
        # Create root dataset to hold boot filesystem
        zfs create -o mountpoint=/boot -o compression=zle -o atime=off -o xattr=sa boot/ubuntu
        # Enable auto snapshots with zfs-auto-snapshot
        zfs set com.sun:auto-snapshot=true boot/ubuntu
        # Set threshold for zfs-auto-snapshot
        zfs set com.sun:snapshot-threshold=2000000 boot/ubuntu
fi

# Create swap in zfs
if [ ${SIZE_ZVOL} != 0 ]; then
        zfs create -V ${SIZE_ZVOL}M -b $(getconf PAGESIZE) \
              -o compression=zle \
              -o primarycache=metadata \
              -o secondarycache=none \
              -o sync=always \
                          -o logbias=throughput \
              -o com.sun:auto-snapshot=false rpool/SWAP
fi

echo "--------------------- $(tput setaf 1)About to debootstrap into /mnt/zfs$(tput sgr0) --------------------"
df -h
echo "--------------------- $(tput setaf 1)About to debootstrap into /mnt/zfs$(tput sgr0) --------------------"
zpool status -v
zfs list -t all
echo "------- $(tput setaf 1)Please check the above listings to be sure they're right$(tput sgr0) ------------"
echo "------- $(tput setaf 3)Press <enter> About to debootstrap into /mnt/zfs$(tput sgr0) --------------------"
read QUIT

# Install core system - need wget to get signing keys in Setup.sh
debootstrap --arch=amd64 --include=wget ${SUITE} /mnt/zfs ${DEBOOTSTRAP}

# Ugly hack to use same ssh host keys as build-host system - saves replacing known_hosts entries
# Copy build-host ssh keys to new debootstrap, to be moved into /etc/ssh after Setup.sh configuration
if [ "ZZ${COPY_SSH}" = "ZZy" ]; then
        cp -av /etc/ssh /mnt/zfs
fi

# ======== Now create Setup.sh script ===============================================================
#       Setup.sh                                : To use inside chroot - NOTE this runs when we actually chroot into /mnt/zfs
cat > /mnt/zfs/root/Setup.sh << __EOFSETUP__
#!/bin/bash
export BOXNAME=${BOXNAME}
export SYSNAME=${SYSNAME}
export LUKS=${LUKS}
export COPY_SSH=${COPY_SSH}
export PASSPHRASE=${PASSPHRASE}
export UEFI=${UEFI}
export SUITE=${SUITE}
export USERNAME=${USERNAME}
export UPASSWORD=${UPASSWORD}
export SSHPUBKEY="${SSHPUBKEY}"
export SIZE_SWAP=${SIZE_SWAP}
export SIZE_ZVOL=${SIZE_ZVOL}
export SWAPRESUME=${SWAPRESUME}
export USE_ZSWAP=${USE_ZSWAP}
export PARTITION_EFI=${PARTITION_EFI}
export PARTITION_GRUB=${PARTITION_GRUB}
export PARTITION_BOOT=${PARTITION_BOOT}
export PARTITION_SWAP=${PARTITION_SWAP}
export PARTITION_DATA=${PARTITION_DATA}
export PARTITION_RSVD=${PARTITION_RSVD}
__EOFSETUP__

for DISK in `seq 1 ${#DISKS[@]}` ; do
        echo "DISKS[${DISK}]=${DISKS[${DISK}]}" >> /mnt/zfs/root/Setup.sh
done

# Note use of ' for this section to avoid replacing $variables - did not use ' above
cat >> /mnt/zfs/root/Setup.sh << '__EOFSETUP__'

# Stuff to do after a basic debootstrap
set -x
# Log everything we do
exec > >(tee -a /root/Setup.log) 2>&1

# Proxy
if [ ${PROXY} ]; then
        # This is for apt-get
        echo 'Acquire::http::proxy "${PROXY}";' > /etc/apt/apt.conf.d/03proxy
fi

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
EC2=`fgrep ec2 /etc/apt/sources.list.orig | fgrep ${SUITE} | head -1 | sed 's/^.*\/\///; s/ ${SUITE}.*//'`
if [ "ZZ${EC2}" = "ZZ" ]; then
        # Not Amazon AWS, so need a source
    EC2=archive.ubuntu.com/ubuntu
        if [ ${SUITE} = trusty ]; then
                PLYMOUTH="plymouth-theme-solar"
        else
                PLYMOUTH="plymouth-theme-ubuntu-logo plymouth-label"
        fi
else
        # Amazon AWS, so EC2 is already pointing at right local source
        PLYMOUTH=""
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
mkdir -p /tmp/fakestart
ln -s /bin/true /tmp/fakestart/initctl
ln -s /bin/true /tmp/fakestart/invoke-rc.d
ln -s /bin/true /tmp/fakestart/restart
ln -s /bin/true /tmp/fakestart/start
ln -s /bin/true /tmp/fakestart/stop
ln -s /bin/true /tmp/fakestart/start-stop-daemon
ln -s /bin/true /tmp/fakestart/service
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
localepurge         localepurge/use-dpkg-feature boolean true
locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8
localepurge     localepurge/quickndirtycalc  boolean true
localepurge     localepurge/mandelete   boolean true
EOFLOCALE

cat /tmp/selections | debconf-set-selections
echo "--- apt-get update"
apt-get update > /dev/null
apt-get -y install localepurge language-pack-en-base
locale-gen en_US en_US.UTF-8
if ! [ -e /etc/default/locale ]; then
        cat > /etc/default/locale << EOF
LC_ALL=en_US.UTF-8
LANG=en_US.UTF-8
LANGUAGE=en_US
EOF
fi
echo "America/New_York" > /etc/timezone
cp -f /usr/share/zoneinfo/US/Eastern /etc/localtime
echo "${SYSNAME}" > /etc/hostname
echo "127.0.1.1 ${SYSNAME}.local        ${SYSNAME}" >> /etc/hosts

apt-get -y install ubuntu-minimal software-properties-common

if [ ${SUITE} = trusty ]; then
        apt-add-repository --yes ppa:zfs-native/stable
        echo "--- apt-get update"
        apt-get update > /dev/null
fi


apt-get -y --no-install-recommends install openssh-server mdadm gdisk parted linux-{headers,image}-generic \
  lvm2 debian-keyring openssh-blacklist-extra most screen ntp vim git openssl openssl-blacklist \
  openssh-blacklist htop build-essential whois avahi-{daemon,dnsconfd,utils} libnss-mdns mlocate \
  bootlogd ubuntu-standard apt-transport-https bash-completion command-not-found friendly-recovery \
  iputils-tracepath irqbalance manpages uuid-runtime apparmor whois grub-pc-bin \
  acpi-support acpi most ${PLYMOUTH}
 # For 16.04/xenial grub-efi-amd64 fails on non-uefi systems
if [ "ZZ${UEFI}" = "ZZy" ]; then
        apt-get -y --no-install-recommends install grub-efi-amd64 efibootmgr
else
        apt-get -y --no-install-recommends install grub-pc efibootmgr
fi

# Ugly hack to use same ssh host keys as build-host system - saves replacing known_hosts entries
# Copy build-host ssh keys to new debootstrap, to be moved into /etc/ssh after Setup.sh configuration
if [ "ZZ${COPY_SSH}" = "ZZy" ]; then
        cp -av /ssh/* /etc/ssh
        rm -rf /ssh
fi

# Set up mdadm - clear out any previous array definitions
cat /etc/mdadm/mdadm.conf | fgrep -v ARRAY > /tmp/ttt
mv /tmp/ttt /etc/mdadm/mdadm.conf
mdadm --detail --scan >> /etc/mdadm/mdadm.conf

# spl package (from ubuntu-zfs) provides /etc/hostid
rm -f /etc/hostid
if [ ${SUITE} = trusty ]; then
        apt-get -y --no-install-recommends install ubuntu-zfs ubuntu-extras-keyring
fi
if [ ${SUITE} = xenial ]; then
        apt-get -y --no-install-recommends install zfsutils-linux spl zfs-zed
        modprobe zfs
fi
apt-get -y install zfs-initramfs

# Allow read-only zfs commands with no sudo password
cat /etc/sudoers.d/zfs | sed -e 's/#//' > /etc/sudoers.d/zfsALLOW

# Create swap
if [ ${SIZE_SWAP} != 0 ]; then
        if [ "ZZ${LUKS}" = "ZZy" ]; then
                echo "Create encrypted SWAP ${BOXNAME}_swap on top of ${BOXNAME}:swap"
                mkswap -L "${BOXNAME}_swap" /dev/mapper/${BOXNAME}:swap
                [ ${SWAPRESUME} = y ] && echo "RESUME=/dev/mapper/${BOXNAME}:swap" > /etc/initramfs-tools/conf.d/resume
        else
                mkswap -L "${BOXNAME}_swap" /dev/md/${BOXNAME}:swap
                [ ${SWAPRESUME} = y ] && echo "RESUME=/dev/md/${BOXNAME}:swap" > /etc/initramfs-tools/conf.d/resume
        fi
fi
if [ ${SIZE_ZVOL} != 0 ]; then
        mkswap -L "${BOXNAME}_zwap"  /dev/zvol/rpool/SWAP
fi

# Shutdown initramfs network before passing control to regular Ubuntu scripts
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

if [ "ZZ${LUKS}" = "ZZy" ]; then
        apt-get -y install cryptsetup
        if [ "`cat /proc/cpuinfo | fgrep aes`" != "" ] ; then
                echo "aesni-intel" >> /etc/modules
                echo "aesni-intel" >> /etc/initramfs-tools/modules
        fi
        echo "aes-x86_64" >> /etc/modules
        echo "aes-x86_64" >> /etc/initramfs-tools/modules
        if [ ${SIZE_SWAP} != 0 ]; then
                echo "ENV{DM_NAME}==\"${BOXNAME}:swap\", SYMLINK+=\"${BOXNAME}:swap\"" >  /etc/udev/rules.d/99-local-crypt.rules
        fi
        echo "ENV{DM_NAME}==\"${BOXNAME}:rsvd\", SYMLINK+=\"${BOXNAME}:rsvd\"" >> /etc/udev/rules.d/99-local-crypt.rules
        for DISK in `seq 1 ${#DISKS[@]}` ; do
                echo "ENV{DM_NAME}==\"root_crypt${DISK}\", SYMLINK+=\"root_crypt${DISK}\"" >> /etc/udev/rules.d/99-local-crypt.rules
        done

        mkdir /etc/initramfs-tools/scripts/luks
        cp /lib/cryptsetup/scripts/decrypt_derived /etc/initramfs-tools/scripts/luks/get.root_crypt.decrypt_derived
        sed -i "
        { 2 a\
            CRYPT_DEVICE=${BOXNAME}:rsvd \\
        }
        { s/\$1/\${CRYPT_DEVICE}/g }
        " /etc/initramfs-tools/scripts/luks/get.root_crypt.decrypt_derived

        # Force inclusion of cryptsetup
        echo "export CRYPTSETUP=y" > /usr/share/initramfs-tools/conf-hooks.d/forcecryptsetup

        # reduce cryptroot timeout from 180s to 30s and remove dropping to shell if missing device
        # Also ignore fstype check for ${BOXNAME}:rsvd - ZFS safety partition 9
        # That is used as the source key for unlocking all the other luks devices
        sed -i "
        s/slumber=180/slumber=30/g
        s/panic/break # panic/
        /cryptsetup: unknown fstype, bad password or options/ {
        i \
                   if [ \"\$crypttarget\" != \"${BOXNAME}:rsvd\" ] ; then
        N ; N ; N ; a\
                   fi  # check for ZFS
        }
        " /usr/share/initramfs-tools/scripts/local-top/cryptroot

        # Help update-initramfs to find all encrypted disks for root - remove "return" from get_root_device()
        sed -i '/echo "$device"/ { N ; s!echo "$device"\n\(.*\)return!echo "$device"\n\1# \
        https://newspaint.wordpress.com/2015/03/22/installing-xubuntu-14-04-trusty-on-zfs-with-luks-encryption/\n\1# return! } ' \
        /usr/share/initramfs-tools/hooks/cryptroot

        # Create /etc/crypttab
        echo "${BOXNAME}:rsvd   UUID=$(blkid /dev/md/${BOXNAME}:rsvd -s UUID -o value)  none    luks,discard,noauto" >> /etc/crypttab
        if [ ${SIZE_SWAP} != 0 ]; then
          echo "${BOXNAME}:swap   UUID=$(blkid /dev/md/${BOXNAME}:swap -s UUID -o value)  none    luks,discard,noauto,checkargs=${BOXNAME}:rsvd,keyscript=/lib/cryptsetup/scripts/decrypt_derived" >> /etc/crypttab
        fi
        for DISK in `seq 1 ${#DISKS[@]}` ; do
          echo "root_crypt${DISK} UUID=$(blkid /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA} -s UUID -o value)  none    luks,discard,noauto,checkargs=${BOXNAME}:rsvd,keyscript=/lib/cryptsetup/scripts/decrypt_derived" >> /etc/crypttab
        done

        # Create initramfs cryptroot
        echo "target=${BOXNAME}:rsvd,source=UUID=$(blkid /dev/md/${BOXNAME}:rsvd -s UUID -o value),key=none,discard" > /etc/initramfs-tools/conf.d/cryptroot
        if [ ${SIZE_SWAP} != 0 ]; then
          echo "target=${BOXNAME}:swap,source=UUID=$(blkid /dev/md/${BOXNAME}:swap -s UUID -o value),key=none,discard,keyscript=/scripts/luks/get.root_crypt.decrypt_derived" >> /etc/initramfs-tools/conf.d/cryptroot
        fi
        for DISK in `seq 1 ${#DISKS[@]}` ; do
          echo "target=root_crypt${DISK},source=UUID=$(blkid /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA} -s UUID -o value),rootdev,keyscript=/scripts/luks/get.root_crypt.decrypt_derived" >> /etc/initramfs-tools/conf.d/cryptroot
        done

        #make sure that openssh-server is installed before dropbear
        apt-get -y install dropbear

##### Force dropbear to use dhcp - can also set up real IP
        cat > /etc/initramfs-tools/conf.d/dropbear_network << '__EOFF__'
export IP=dhcp
DROPBEAR=y
CRYPTSETUP=y
BUSYBOX=y
__EOFF__

##### Need the full version of busybox
        cat > /etc/initramfs-tools/hooks/busybox2 << '__EOFF__'
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

# busybox
if [ "${BUSYBOX}" != "n" ] && [ -e /bin/busybox ]; then
        . /usr/share/initramfs-tools/hook-functions
        rm -f ${DESTDIR}/bin/busybox
        copy_exec /bin/busybox /bin
        copy_exec /usr/bin/xargs /bin
fi
__EOFF__
##### Create script to start md arrays no matter what
        cat > /etc/initramfs-tools/scripts/init-premount/zzmdraidforce <<'__EOF__'
#!/bin/sh
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

for md in $(cat /proc/mdstat | grep inactive | cut -d\ -f1); do
        devs="$(cat /proc/mdstat | grep ^${md} | cut -d\ -f5- | sed -e 's/\[[0-9]\]//g' -e 's/sd/\/dev\/sd/g')"
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
/usr/lib/dropbear/dropbearconvert openssh dropbear /etc/ssh/ssh_host_dsa_key ${DESTDIR}/etc/dropbear/dropbear_dss_host_key
/usr/lib/dropbear/dropbearconvert openssh dropbear /etc/ssh/ssh_host_rsa_key ${DESTDIR}/etc/dropbear/dropbear_rsa_host_key
fi
__EOFF__

# Make it executable
chmod a+x /etc/initramfs-tools/hooks/dropbear.fixup2

        # Put SSH pubkey in initramfs
        echo "-----------------------------------------------------------------------------"
        echo "Installing sshpubkey ${SSHPUBKEY}"
        [ ! -e /etc/initramfs-tools/root/.ssh ] && mkdir -p /etc/initramfs-tools/root/.ssh
        echo "${SSHPUBKEY}" >> /etc/initramfs-tools/root/.ssh/authorized_keys
        echo "-----------------------------------------------------------------------------"

else # not LUKS

        # This from https://bugs.launchpad.net/ubuntu/+source/zfs-initramfs/+bug/1530953
        echo 'KERNEL=="sd*[0-9]", IMPORT{parent}=="ID_*", ENV{ID_FS_TYPE}=="zfs_member", SYMLINK+="$env{ID_BUS}-$env{ID_SERIAL}-part%n"' > /etc/udev/rules.d/61-zfs-vdev.rules

        # https://bugs.launchpad.net/ubuntu/+source/zfs-initramfs/+bug/1530953/comments/28
        # HRM - this one isn't working
        # echo 'KERNEL=="sd*[0-9]", IMPORT{parent}=="ID_*", ENV{ID_PART_ENTRY_SCHEME}=="gpt",
        ENV{ID_PART_ENTRY_TYPE}=="6a898cc3-1dd2-11b2-99a6-080020736631", SYMLINK+="$env{ID_BUS}-$env{ID_SERIAL}-part%n"' > /etc/udev/rules.d/60-zfs-vdev.rules
fi # if LUKS

# Create fstab
echo "tmpfs                   /tmp    tmpfs   defaults,noatime,mode=1777      0 0" >> /etc/fstab

if [ ${SIZE_ZVOL} != 0 ]; then
        echo "" >> /etc/fstab
        echo "# ${BOXNAME}_zwap is the zfs SWAP zvol" >> /etc/fstab
        echo "/dev/zvol/rpool/SWAP    none    swap    defaults                        0 0" >> /etc/fstab
fi

if [ ${SIZE_SWAP} != 0 ]; then
        echo "" >> /etc/fstab
        echo "# ${BOXNAME}_swap is the mdadm array of partition ${PARTITION_SWAP} on all drives" >> /etc/fstab
        echo "UUID=$(blkid -t LABEL=${BOXNAME}_swap -s UUID -o value) none swap defaults   0 0" >>/etc/fstab
fi

if [ "ZZ${UEFI}" = "ZZy" ]; then
        echo "" >> /etc/fstab
        for DISK in `seq 1 ${#DISKS[@]}` ; do
                echo "UUID=$(blkid -t LABEL=EFI_${DISK} -s UUID -o value) /boot/efi_${DISK} vfat defaults,nobootwait,nofail 0 0" >>/etc/fstab
        done
fi

# Set GRUB to use zfs - enable zswap if USE_ZSWAP="zswap parameters"
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT=\"net.ifnames=0 rpool=rpool bootfs=rpool\/ROOT\/ubuntu boot=zfs bootdegraded=true ${USE_ZSWAP} splash\"/" /etc/default/grub

if [ "ZZ${LUKS}" = "ZZy" ]; then
        # Export and import boot zpool to populate /etc/zfs/zpool.cache
        zpool export boot
        zpool import -f -d /dev/disk/by-id boot
fi

# Clear existing EFI NVRAM boot order, it's more than likely incorrect for our needs by now
# Also sets 10 second timeout for EFI boot menu just in case it was set to too low value earlier
if [ -e /sys/firmware/efi ]; then
        efibootmgr --delete-bootorder --timeout 10 --write-signature

        # Remove unwanted, existing boot entries from EFI list
        for f in `seq 0 6`; do
                efibootmgr --delete-bootnum --bootnum 000${f}
        done
fi

# Install and update grub
update-grub
for DISK in `seq 1 ${#DISKS[@]}` ; do
        sgdisk -C /dev/disk/by-id/${DISKS[${DISK}]}
        sgdisk -h ${PARTITION_GRUB} /dev/disk/by-id/${DISKS[${DISK}]}

        # Toggle boot flag is for MBR only
        # sfdisk --force -A${PARTITION_GRUB} /dev/disk/by-id/${DISKS[${DISK}]}

        if [ "ZZ${UEFI}" = "ZZy" ]; then
                mkdir -p /boot/efi_${DISK}
                mount /boot/efi_${DISK}
                echo "Ignore errors from grub-install here if not in EFI mode"

                grub-install --boot-directory=/boot --bootloader-id="EFI disk ${DISK}" --no-floppy --recheck --target=x86_64-efi --efi-directory=/boot/efi_${DISK} /dev/disk/by-id/${DISKS[${DISK}]}
                mkdir -p /boot/efi_${DISK}/EFI/BOOT
                cp -a "/boot/efi_${DISK}/EFI/EFI disk ${DISK}/grubx64.efi" /boot/efi_${DISK}/EFI/BOOT/bootx64.efi
                [ -d /sys/firmware/efi ] && efibootmgr --create --disk /dev/disk/by-id/${DISKS[${DISK}]} --part${PARTITION_EFI} --write-signature --loader '\EFI\BOOT\bootx64.efi' --label "EFI fallback disk ${DISK}"
                umount /boot/efi_${DISK}
        fi
        grub-install /dev/disk/by-id/${DISKS[${DISK}]}
done
update-grub

# echo "--- apt-get update"
# apt-get update > /dev/null
# apt-get -y install zfs-initramfs
update-initramfs -c -k all

# Niceties - taken from Installerbox system - Install_BASICS.sh
# Nicer PS1 prompt
cat >> /etc/bash.bashrc << EOF

PS1="${debian_chroot:+($debian_chroot)}\[\$(tput setaf 2)\]\u@\[\$(tput bold)\]\[\$(tput setaf 5)\]\h\[\$(tputsgr0)\]\[\$(tput setaf 7)\]:\[\$(tput bold)\]\[\$(tput setaf 4)\]\w\[\$(tput setaf 7)\]\\$ \[\$(tput sgr0)\]"

# https://unix.stackexchange.com/questions/99325/automatically-save-bash-command-history-in-screen-session
PROMPT_COMMAND="history -a; history -c; history -r; \${PROMPT_COMMAND}"
HISTSIZE=5000
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
EOF
cat >> /etc/skel/.bashrc << EOF

PS1="${debian_chroot:+($debian_chroot)}\[\$(tput setaf 2)\]\u@\[\$(tput bold)\]\[\$(tput setaf 5)\]\h\[\$(tputsgr0)\]\[\$(tput setaf 7)\]:\[\$(tput bold)\]\[\$(tput setaf 4)\]\w\[\$(tput setaf 7)\]\\$ \[\$(tput sgr0)\]"

# https://unix.stackexchange.com/questions/99325/automatically-save-bash-command-history-in-screen-session
PROMPT_COMMAND="history -a; history -c; history -r; \${PROMPT_COMMAND}"
HISTSIZE=5000
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
alias l='ls -la'
alias lt='ls -lat | head -25'
alias vhwinfo='wget --no-check-certificate https://vhwinfo.com/vhwinfo.sh -O - -o /dev/null|bash'
EOF
[ ! -e /home/${USERNAME} ] && useradd -c "Main user" -p `echo "${UPASSWORD}" | mkpasswd -m sha-512 --stdin` --home-dir /home/${USERNAME} --user-group --groups adm,sudo,dip,plugdev --create-home --skel /etc/skel --shell /bin/bash ${USERNAME}

mkdir -p /root/.ssh /home/${USERNAME}/.ssh
echo "${SSHPUBKEY}" >> /root/.ssh/authorized_keys
cp /root/.ssh/authorized_keys /home/${USERNAME}/.ssh
cp /root/.bash_aliases /home/${USERNAME}


chmod 700 /root/.ssh /home/${USERNAME}/.ssh
chown -R ${USERNAME}.${USERNAME} /home/${USERNAME}

# Ugh - want most as pager
update-alternatives --set pager /usr/bin/most

# Final update
apt-get -f install
apt-get -y --force-yes upgrade

exit
__EOFSETUP__
chmod +x /mnt/zfs/root/Setup.sh
# ======== END create Setup.sh script ===============================================================

# Here are a couple of helper scripts
# Replace-failed-drive.sh - goes into /root in new system, helps to replace a failed drive
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
export LUKS=${LUKS}
export ZERO=${ZERO}
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

# Zero entire disk
if [ "ZZ${ZERO}" = "ZZy" ]; then
        # urandom is limited, so use frandom module
        [ ! -e /var/lib/dpkg/info/build-essential.list ] && apt-get -y install build-essential
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

        dd if=/dev/frandom of=/dev/disk/by-id/${NEWDISK} bs=512 count=$(blockdev --getsz /dev/disk/by-id/${NEWDISK}) &
        WAITPIDS="${WAITPIDS} "$!
fi

# Clear any old zpool info
zpool labelclear -f /dev/disk/by-id/${NEWDISK} > /dev/null 2>&1
[ -e /dev/disk/by-id/${NEWDISK}-part${PARTITION_DATA} ] && zpool labelclear -f /dev/disk/by-id/${NEWDISK}-part${PARTITION_DATA} > /dev/null 2>&1

mdadm --zero-superblock --force /dev/disk/by-id/${NEWDISK}*
[ -e /dev/disk/by-id/${NEWDISK}-part${PARTITION_BOOT} ] && mdadm --zero-superblock --force /dev/disk/by-id/${NEWDISK}-part${PARTITION_BOOT} > /dev/null 2>&1
[ -e /dev/disk/by-id/${NEWDISK}-part${PARTITION_SWAP} ] && mdadm --zero-superblock --force /dev/disk/by-id/${NEWDISK}-part${PARTITION_SWAP} > /dev/null 2>&1
[ -e /dev/disk/by-id/${NEWDISK}-part${PARTITION_RSVD} ] && mdadm --zero-superblock --force /dev/disk/by-id/${NEWDISK}-part${PARTITION_RSVD} > /dev/null 2>&1


# Clear any old LUKS or mdadm info
[ -e /dev/disk/by-id/${NEWDISK}-part${PARTITION_DATA} ] && dd if=/dev/zero of=/dev/disk/by-id/${NEWDISK}-part${PARTITION_DATA} bs=512 count=20480 > /dev/null 2>&1
[ -e /dev/disk/by-id/${NEWDISK}-part${PARTITION_SWAP} ] && dd if=/dev/zero of=/dev/disk/by-id/${NEWDISK}-part${PARTITION_SWAP} bs=512 count=20480 > /dev/null 2>&1
[ -e /dev/disk/by-id/${NEWDISK}-part${PARTITION_RSVD} ] && dd if=/dev/zero of=/dev/disk/by-id/${NEWDISK}-part${PARTITION_RSVD} bs=512 count=4096 > /dev/null 2>&1

sgdisk -Z /dev/disk/by-id/${NEWDISK}
sgdisk -R /dev/disk/by-id/${NEWDISK} /dev/disk/by-id/${GOODDISK} -G
partprobe /dev/disk/by-id/${NEWDISK}

# Only if we have UEFI
if [ "ZZ${UEFI}" = "ZZy" ]; then
        sgdisk -c${PARTITION_EFI}:"EFI_${NEW}" /dev/disk/by-id/${NEWDISK}
fi

# Always have these two
sgdisk -c${PARTITION_GRUB}:"GRUB_${NEW}" /dev/disk/by-id/${NEWDISK}
sgdisk -c${PARTITION_RSVD}:"RSVD_${NEW}" /dev/disk/by-id/${NEWDISK}

# Encrypted means /boot on partition raided, and rsvd is raided
if [ "ZZ${LUKS}" = "ZZy" ]; then
        sgdisk -c${PARTITION_BOOT}:"BOOT_${NEW}" /dev/disk/by-id/${NEWDISK}
fi

# Only if swap partition

if [ ${SIZE_SWAP} != 0 ]; then
        sgdisk -c${PARTITION_SWAP}:"SWAP_${NEW}" /dev/disk/by-id/${NEWDISK}
fi
sgdisk -c${PARTITION_DATA}:"ZFS_${NEW}" /dev/disk/by-id/${NEWDISK}
partprobe /dev/disk/by-id/${NEWDISK}

if [ "ZZ${LUKS}" = "ZZy" ]; then
        mdadm --manage /dev/md/${BOXNAME}:boot --add /dev/disk/by-id/${NEWDISK}-part${PARTITION_BOOT}
        mdadm --manage /dev/md/${BOXNAME}:rsvd --add /dev/disk/by-id/${NEWDISK}-part${PARTITION_RSVD}
fi
if [ ${SIZE_SWAP} != 0 ]; then
        mdadm --manage /dev/md/${BOXNAME}:swap --add /dev/disk/by-id/${NEWDISK}-part${PARTITION_SWAP}
fi

mkfs.vfat -v -F32 -s2 -n "EFI_${NEW}" /dev/disk/by-id/${NEWDISK}-part${PARTITION_EFI}

if [ "ZZ${LUKS}" = "ZZy" ]; then
        # Replace failed zpool drive/partition with new encrypted partition
        OLDPART="/dev/mapper/`zpool status -v | fgrep FAULTED | tr -s ' ' | cut -d' ' -f2`"
        NEWPART=/dev/mapper/root_crypt${NEW}

        # Create new root_crypt${NEW}, add derived key to it
        echo ${PASSPHRASE} | cryptsetup --batch-mode luksFormat -c aes-xts-plain64 -s 512 -h sha512 /dev/disk/by-id/${NEWDISK}-part${PARTITION_DATA}
        echo ${PASSPHRASE} | cryptsetup luksOpen /dev/disk/by-id/${NEWDISK}-part${PARTITION_DATA} root_crypt${NEW}
        ln -sf /dev/mapper/root_crypt${NEW} /dev/root_crypt${NEW}
        /lib/cryptsetup/scripts/decrypt_derived ${BOXNAME}:rsvd > /tmp/key
        echo ${PASSPHRASE} | cryptsetup luksAddKey /dev/disk/by-id/${NEWDISK}-part${PARTITION_DATA} /tmp/key

        # Recreate crypttab
        # Remove old disk
        cp /etc/crypttab /etc/crypttab.backup
        cat /etc/crypttab.backup | fgrep -v `basename ${OLDPART}` > /etc/crypttab

        # Add new disk
        echo "root_crypt${NEW}  UUID=$(blkid /dev/disk/by-id/${NEWDISK}-part${PARTITION_DATA} -s UUID -o value) none    luks,discard,noauto,checkargs=${BOXNAME}:swap,keyscript=/lib/cryptsetup/scripts/decrypt_derived" >> /etc/crypttab

        # Recreate cryptroot
        # Remove old disk
        cp /etc/initramfs-tools/conf.d/cryptroot /etc/initramfs-tools/conf.d/cryptroot.backup
        cat /etc/initramfs-tools/conf.d/cryptroot.backup | fgrep -v `basename ${OLDPART}` > /etc/initramfs-tools/conf.d/cryptroot

        # Add new disk
        echo "target=root_crypt${NEW},source=UUID=$(blkid /dev/disk/by-id/${NEWDISK}-part${PARTITION_DATA} -s UUID -o value),rootdev,keyscript=/scripts/luks/get.root_crypt.decrypt_derived" >> /etc/initramfs-tools/conf.d/cryptroot
else
        # Replace failed zpool drive/partition with new drive/partition
        OLDPART="/`zpool status -v | fgrep was | cut -d'/' -f2-`"
        # NEWPART="/dev/disk/by-id/`ls -al /dev/disk/by-id | fgrep ${NEWDISK}-part${PARTITION_DATA} | sed -e 's/.*\(ata.*\) ->.*/\1/'`"
        NEWPART="/dev/disk/by-id/${NEWDISK}-part${PARTITION_DATA}"
        ln -sf /dev/disk/by-id/${NEWDISK}-part${PARTITION_DATA} /dev
fi

# Recreate fstab /boot/efi entries
# Add new disk
if [ "ZZ${UEFI}" = "ZZy" ]; then
        mkdir -p /boot/efi_${NEW}
        echo "UUID=$(blkid -t LABEL=EFI_${NEW} -s UUID -o value) /boot/efi_${NEW} vfat defaults,nobootwait,nofail 0 0" >>/etc/fstab
        mount /boot/efi_${NEW}

        # Copy EFI stuff from good disk to new disk (/boot/efi_${NEW})
        cp -a `cat /etc/fstab | fgrep "\`blkid /dev/disk/by-id/${GOODDISK}-part${PARTITION_EFI} -s UUID -o value\`" | cut -d' ' -f2`/* /boot/efi_${NEW}

        # Remove old /boot/efi_ (not mounted because ... disk is gone) dir from fstab
        OLDEFI=`( mount | fgrep /boot/efi_ | cut -d' ' -f3 ; fgrep /boot/efi_ /etc/fstab | cut -d' ' -f2 ) | sort | uniq -u`
        umount -f ${OLDEFI}
        rm -rf ${OLDEFI}
        cp /etc/fstab /etc/fstab.backup
        cat /etc/fstab.backup | fgrep -v ${OLDEFI} > /etc/fstab
fi

zpool replace rpool ${OLDPART} ${NEWPART}
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
export LUKS=${LUKS}
export PASSPHRASE=${PASSPHRASE}
export UEFI=${UEFI}
export USERNAME=${USERNAME}
export UPASSWORD=${UPASSWORD}
export SSHPUBKEY="${SSHPUBKEY}"
export SIZE_SWAP=${SIZE_SWAP}
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

if [ "ZZ${LUKS}" = "ZZy" ]; then
        if [ ${SIZE_SWAP} != 0 ]; then
                echo ${PASSPHRASE} | cryptsetup luksOpen /dev/md/${BOXNAME}:swap ${BOXNAME}:swap
                ln -sf /dev/mapper/${BOXNAME}:swap /dev
        fi
        echo ${PASSPHRASE} | cryptsetup luksOpen /dev/md/${BOXNAME}:rsvd ${BOXNAME}:rsvd
        ln -sf /dev/mapper/${BOXNAME}:rsvd /dev
        for DISK in `seq 1 ${#DISKS[@]}` ; do
                echo ${PASSPHRASE} | cryptsetup luksOpen /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA} root_crypt${DISK}
                ln -sf /dev/mapper/root_crypt${DISK} /dev/root_crypt${DISK}
                # /boot partition is NOT encrypted, so use by-id
                ln -sf /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_BOOT} /dev
        done
        zpool import -f -d /dev/mapper -R /mnt/zfs rpool
else
        for DISK in `seq 1 ${#DISKS[@]}` ; do
                ln -sf /dev/disk/by-id/${DISKS[${DISK}]}-part${PARTITION_DATA} /dev
        done
        zpool import -f -d /dev/disk/by-id -R /mnt/zfs rpool
fi # LUKS

zfs mount rpool/ROOT/ubuntu

if [ "ZZ${LUKS}" = "ZZy" ]; then
        rm -rf /mnt/zfs/boot/grub
        zpool import -f -d /dev/disk/by-id -R /mnt/zfs boot
fi


[ ! -e /mnt/zfs/etc/mtab ] && ln -s /proc/mounts /mnt/zfs/etc/mtab
mount -o bind /proc /mnt/zfs/proc
mount -o bind /dev /mnt/zfs/dev
mount -o bind /dev/pts /mnt/zfs/dev/pts
mount -o bind /sys /mnt/zfs/sys

# Only chroot if we passed -y into script
if [ "$1" = "-y" ]; then
        chroot /mnt/zfs /bin/bash --login
else
        bash --login
fi
umount /mnt/zfs/boot/efi_* > /dev/null 2>&1
umount /mnt/zfs/sys
umount /mnt/zfs/dev/pts
umount /mnt/zfs/proc
umount /mnt/zfs/dev

if [ "ZZ${LUKS}" = "ZZy" ]; then
        zpool export boot
fi
zpool export rpool
if [ "ZZ${LUKS}" = "ZZy" ]; then
        if [ ${SIZE_SWAP} != 0 ]; then
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
zfs snap rpool/ROOT/ubuntu@debootstrap
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

# After exit from chroot continue from here
umount /mnt/zfs/sys
umount /mnt/zfs/dev/pts
umount /mnt/zfs/proc
umount /mnt/zfs/dev

if [ "ZZ${LUKS}" = "ZZy" ]; then
        echo "# ***************************************************************************************"
        echo "#"
        echo "#  Do not forget to save (and encrypt) the LUKS header backup files"
        echo "#"
        for LUKSBACKUP in LUKS-header* ; do
                echo "#  ${LUKSBACKUP}"
                cp ${LUKSBACKUP} /mnt/zfs/root
        done
        chmod 700 /mnt/zfs/root/LUKS*
        echo "#"
        echo "# ***************************************************************************************"
fi

if [ "ZZ${LUKS}" = "ZZy" ]; then
        zpool export boot
fi
zpool export rpool

exit


