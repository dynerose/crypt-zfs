#!/bin/bash
#passwd
#sudo su
# save some precious memory ;)
systemctl stop lightdm && 
apt update &&
apt install --yes openssh-server net-tools &&
sleep 3
cat >> /etc/ssh/sshd_config << EOF
Port 22
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::
EOF
service sshd start &&

BIOS_DISK="1"
BOOT_DISK="2"
EFI_DISK="3"
CRYPT_DISK="4"
OTHER_DISK="9"
CRYPTED="YES"

RPOOL="rpool"
USERNAME="sa"
PASSWORD="sa"
TARGET_HOSTNAME="test"
IFACE="ens33"
DISK="/dev/sda"

MBRBOOT=MBR
GPTBOOT=GPT
GPTBOOT=NO

apt update &&
apt install --yes debootstrap zfsutils-linux zfs-initramfs software-properties-common gdisk mdadm &&
apt install --yes cryptsetup &&
mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {} &&
#zpool destroy $RPOOL &&
#rm -R /mnt/boot &&

# clear
sudo sgdisk --clear $DISK  &&
  sleep 2
sgdisk --zap $DISK &&
  sleep 2
# Create new partition table. Should align to 2048-byte alignment
sudo sgdisk --largest-new=1 $DISK &&
  sleep 2

sgdisk -o $DISK &&
  sleep 2
sgdisk -n$BIOS_DISK:1M:+1M -t$BIOS_DISK:ef02  -c $BIOS_DISK:"BIOS Boot Partition" $DISK  &&
  sleep 2
# for /boot 
sgdisk -n$BOOT_DISK:0:+512M -t$BOOT_DISK:8300 -c $BOOT_DISK:"Linux /boot" $DISK  &&
  sleep 2
  # BOOT
sgdisk -n$EFI_DISK:0:+512M -t$EFI_DISK:EF00 -c $EFI_DISK:"EFI System Partition" $DISK  &&
  sleep 2 
  # EFI
sgdisk -n$OTHER_DISK:-8M:0 -t$OTHER_DISK:BF07   -c $OTHER_DISK:"required by ZFS" $DISK  &&
  sleep 2
  # The 9th partition is Solaris Reserved 1. It is required by ZFS (yet, I don’t know why).
sgdisk -n$CRYPT_DISK:0:0 -t$CRYPT_DISK:8300 -c $CRYPT_DISK:"Linux data luks/zfs/root" $DISK  &&
  sleep 2
  # everything else

sgdisk -p $DISK &&
  sleep 2
sgdisk -A $BOOT_DISK:set:2 $DISK &&
  sleep 2

# Now let’s setup the crypto part:
if [[ "$CRYPTED" == "YES" ]]
  then
	# zpool destroy $RPOOL &&
	echo "CRYPTED YES"
	# cryptsetup luksClose  rpool_crypt &&
	echo -n "sa" | cryptsetup luksFormat  -q -c aes-xts-plain64 -s 512 -h sha512 ${DISK}$CRYPT_DISK  &&
	#cryptsetup luksFormat  -q -c aes-xts-plain64 -s 512 -h sha512 ${DISK}$CRYPT_DISK  &&
	sleep 2
	echo -n "sa" | cryptsetup luksOpen ${DISK}$CRYPT_DISK rpool_crypt  &&
	sleep 2
# And now the ZFS thingy (full copy from ZoL project plus some additional steps for LUKS):
	fi

	


zpool create -o ashift=12 -O atime=off -O canmount=off -O compression=lz4 -O normalization=formD -O mountpoint=/ -R /mnt $RPOOL /dev/mapper/rpool_crypt
sleep 2
zfs create -o canmount=off -o mountpoint=none $RPOOL/ROOT &&
zfs create -o canmount=noauto -o mountpoint=/ $RPOOL/ROOT/ubuntu &&
zfs mount $RPOOL/ROOT/ubuntu &&
zfs create -o setuid=off $RPOOL/home &&
zfs create -o mountpoint=/root $RPOOL/home/root &&
zfs create -o canmount=off -o setuid=off -o exec=off $RPOOL/var &&
zfs create -o com.sun:auto-snapshot=false $RPOOL/var/cache &&
zfs create $RPOOL/var/log &&
zfs create $RPOOL/var/spool &&
zfs create -o com.sun:auto-snapshot=false -o exec=on $RPOOL/var/tmp &&

chmod 1777 /mnt/var/tmp &&

mke2fs -t ext2 ${DISK}$BOOT_DISK &&
sleep 5
mkdir /mnt/boot &&
sleep 5
mount ${DISK}$BOOT_DISK /mnt/boot &&
sleep 5

debootstrap xenial /mnt &&
# Prepare the boot and CRYPT partitions:
if [[ "$CRYPTED" == "YES" ]]
	then
		echo "/dev/mapper/rpool_crypt / zfs defaults 0 0"  >> /mnt/etc/fstab
	fi
echo "PARTUUID=$(blkid -s PARTUUID -o value ${DISK}$BOOT_DISK) /boot auto defaults 0 0" >> /mnt/etc/fstab

# Prepare the boot and EFI partitions:
#if [[ "$GPTBOOT" == "EFI" ]]#
#		mkdosfs -F 32 -n EFI ${DISK}$EFI_DISK &&
#		echo "PARTUUID=$(blkid -s PARTUUID -o value ${DISK}$EFI_DISK) /boot/efi vfat defaults 0 1" >> /mnt/etc/fstab
#	fi

zfs set devices=off rpool &&

# You may want to take a snapshot at this point and also during the process if you wish so
zfs snapshot rpool/ROOT/ubuntu@bootstrap &&
zfs list -t snapshot &&

#Prepare the chroot:

echo "$TARGET_HOSTNAME" > /mnt/etc/hostname
sed -i 's,localhost,localhost\n127.0.1.1\t'$TARGET_HOSTNAME',' /mnt/etc/hosts

#Set the network interace
#Do not apply this in case you are going to use only WiFi.
NIF=$(route | grep '^default' | grep -o '[^ ]*$')
cat << EOF > /mnt/etc/network/interfaces.d/$NIF
auto $NIF
iface $NIF inet dhcp
EOF

#Chroot into your future system

mount --rbind /dev  /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys  /mnt/sys &&
chroot /mnt /bin/bash --login <<'EOCHROOT'
cat > /etc/apt/sources.list << EOLIST
deb http://archive.ubuntu.com/ubuntu xenial main universe
deb-src http://archive.ubuntu.com/ubuntu xenial main universe

deb http://security.ubuntu.com/ubuntu xenial-security main universe
deb-src http://security.ubuntu.com/ubuntu xenial-security main universe

deb http://archive.ubuntu.com/ubuntu xenial-updates main universe
deb-src http://archive.ubuntu.com/ubuntu xenial-updates main universe
EOLIST
# Setup the system:

BIOS_DISK="1"
BOOT_DISK="2"
EFI_DISK="3"
CRYPT_DISK="4"
OTHER_DISK="9"
CRYPTED="YES"

RPOOL="rpool"
USERNAME="sa"
PASSWORD="sa"
TARGET_HOSTNAME="test"
IFACE="ens33"
DISK="/dev/sda"

MBRBOOT="MBR"
GPTBOOT=NO#GPT
GPTBOOT="NO"

ln -s /proc/self/mounts /etc/mtab &&
apt update &&
locale-gen en_US.UTF-8 &&
echo 'LANG="en_US.UTF-8"' > /etc/default/locale &&
dpkg-reconfigure tzdata &&
apt install --yes --no-install-recommends linux-image-generic wget nano &&
apt install --yes zfs-initramfs &&
apt install --yes openssh-server mc &&

wget -q -O /etc/cron.hourly/zfs-check https://gist.githubusercontent.com/fire/65f7aa33b91d3af2aef0/raw/a0309ef9a6bec26b497b2ee7e00aaa2889310384/zfs-check.sh &&
wget -q -O /etc/cron.monthly/zfs-scrub https://gist.githubusercontent.com/fire/65f7aa33b91d3af2aef0/raw/5b0904343897b1410fd57239879a0f43ff634883/zfs-scrub.sh &&
chmod 755 /etc/cron.hourly/zfs-check /etc/cron.monthly/zfs-scrub &&
wget -q -O /etc/sudoers.d/zfs https://gist.githubusercontent.com/fire/65f7aa33b91d3af2aef0/raw/36a2b9e37819abffc6bfc2a9a36859afabf47754/zfs.sudoers &&
chmod 440 /etc/sudoers.d/zfs &&
apt install --yes dosfstools &&

if [[ "$GPTBOOT" == "GPT" ]]
  then mkdosfs -F 32 -n EFI /dev/${DISKID}3 &&
  mkdir /boot/efi &&
  echo PARTUUID=$(blkid -s PARTUUID -o value /dev/${DISKID}3) /boot/efi vfat defaults 0 1 >> /etc/fstab &&
  mount /boot/efi &&
  apt install --yes grub-efi-amd64 &&
  sleep 2
fi
ln -s mapper/rpool_crypt /dev/rpool_crypt &&
sleep 2
# if [[ "$MBRBOOT" == "MBR" ]]
#  then
	#	apt install --yes grub-pc &&
	DEBIAN_FRONTEND=noninteractive apt-get -y install grub-pc &&
	echo "grub-pc grub-pc/kopt_extracted boolean true" | debconf-set-selections
	echo "grub-pc grub2/linux_cmdline string" | debconf-set-selections
	echo "grub-pc grub-pc/install_devices multiselect $DISK" | debconf-set-selections
	echo "grub-pc grub-pc/install_devices_failed_upgrade boolean true" | debconf-set-selections
	echo "grub-pc grub-pc/install_devices_disks_changed multiselect $DISK" | debconf-set-selections
	dpkg-reconfigure -f noninteractive grub-pc &&
  
  
  sleep 2
# fi
addgroup --system lpadmin
addgroup --system sambashare

echo /dev/disk/by-uuid/$(blkid -s UUID -o value $DISK$BOOT_DISK) /boot ext2 auto defaults 0 1 >> /etc/fstab
if [[ "$CRYPTED" == "YES" ]]
	then
		echo "/dev/mapper/rpool_crypt / zfs defaults 0 0"  >> /etc/fstab
		# 4.7 For LUKS installs only:
		apt install --yes cryptsetup # grub-efi
		echo  rpool_crypt UUID=$(blkid -s UUID -o value $DISK$CRYPT_DISK) none luks > /etc/crypttab
		echo 'ENV{DM_NAME}=="rpool_crypt", SYMLINK+="rpool_crypt"' > /etc/udev/rules.d/99-local.rules # Assure that future kernel updates will succeed by always creating the symbolic link.
		# Without this symbolic link update-grub will complain that is can't find the canonical path and error. 
	fi
# UNCONFIGURED FSTAB FOR BASE SYSTEM
# /dev/disk/by-uuid/736533ad-8b49-43c1-ba06-57c8aeccebf3 /boot/grub auto defaults 0 1
# /dev/mapper/crypt1 / zfs defaults 0 0
# /dev/zvol/rpool/SWAP none swap defaults 0 
# 4.11 Fix filesystem mount ordering
zfs set mountpoint=legacy rpool/var/log
zfs set mountpoint=legacy rpool/var/tmp
cat >> /etc/fstab << EOF
rpool/var/log /var/log zfs defaults 0 0
rpool/var/tmp /var/tmp zfs defaults 0 0
EOF

#mount /boot
#mkdir /boot/efi
#mount /boot/efi

# 4.9 Setup system groups:

PASSWORD='sa'
USERNAME='sa'
adduser $USERNAME --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -a -G adm,cdrom,dip,lpadmin,plugdev,sambashare,sudo $USERNAME


# Step 5: GRUB Installation
# 5.1 Verify that the ZFS root filesystem is recognized:
grub-probe /
#zfs

zfs snapshot rpool/ROOT/ubuntu@pregrub
update-initramfs -c -k all

# 5.3 Optional (but highly recommended): Make debugging GRUB easier:
# vi /etc/default/grub
# Comment out: GRUB_HIDDEN_TIMEOUT=0
# Remove quiet and splash from: GRUB_CMDLINE_LINUX_DEFAULT
# Uncomment: GRUB_TERMINAL=console
# Save and quit.

sed -i 's,GRUB_CMDLINE_LINUX_DEFAULT="quiet splash",GRUB_CMDLINE_LINUX_DEFAULT="boot=zfs nosplash",' /etc/default/grub

# 5.4 Update the boot configuration:
update-grub

#5.5 Install the boot loader
#5.5a For legacy (MBR) booting, install GRUB to the MBR:
if [[ "$MBRBOOT" == "MBR" ]]
  then
  echo "1234"
  grub-install $DISK &&
  sleep 4
fi


#5.5b For UEFI booting, install GRUB:
if [[ "$GPTBOOT" == "GPT" ]]
  then
	grub-install --target=x86_64-efi --efi-directory=/boot/efi \
      --bootloader-id=ubuntu --recheck --no-floppy
  sleep 4
  fi  

apt-get clean
#5.6 Verify that the ZFS module is installed:
ls /boot/grub/*/zfs.mod

# Step 6: First Boot
# 6.1 Snapshot the initial installation:
zfs snapshot rpool/ROOT/ubuntu@install
#6.2 Exit from the chroot environment back to the LiveCD environment:
# Configure SWAP
# change 256M to 4G or more if you have more space, depending on your needs.


zfs create -V 256M -b $(getconf PAGESIZE) -o compression=zle \
      -o logbias=throughput -o sync=always \
      -o primarycache=metadata -o secondarycache=none \
      -o com.sun:auto-snapshot=false rpool/swap &&

# Now you can format and activate swap

mkswap -f /dev/zvol/$RPOOL/swap &&
echo /dev/zvol/$RPOOL/swap none swap defaults 0 0 >> /etc/fstab &&
swapon -av &&
apt dist-upgrade --yes &&
apt update &&
for file in /etc/logrotate.d/* ; do
    if grep -Eq "(^|[^#y])compress" "$file" ; then
        sed -i -r "s/(^|[^#y])(compress)/\1#\2/" "$file"
    fi
done

# Disable root password
usermod -p '*' root

echo 'Exiting chroot.'
EOCHROOT

# Almost there:
mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {} &&
mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {} && 
zpool export $RPOOL

# reboot
