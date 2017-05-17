#!/bin/bash
# test.sh

# Install neccessary packages:
# sudo apt-add-repository universe
# sudo apt update
# sudo apt install zfsutils-linux zfs-initramfs cryptsetup debootstrap dosfstools gdisk mdadm mc nano -y

echo "WARNING!  This script could wipe out all your data, or worse!  I am not responsible for your decisions.  Carefully enter the ID of the disk YOU WANT TO DESTROY in the next step to ensure no data is accidentally lost.  Press Enter to continue."
read DISCLAIMER

lsblk --list -io KNAME,SIZE,MODEL,TYPE
echo "Enter Disk NAME (must match exactly for example only : sda):"
read DISKID
echo "Disk ID set to $DISKID"
while true
do
    read -r -p 'MBR (y/n)?' choice
    case "$choice" in
      n|N) break;;
      y|Y) MBRBOOT=MBR &&
           break;;
      *) echo 'Response not valid';;
    esac
done

while true
do
    read -r -p 'GPT (y/n)?' choice
    case "$choice" in
      n|N) break;;
      y|Y) GPTBOOT=GPT &&
           break;;
      *) echo 'Response not valid';;
    esac
done

echo "Set a name for the ZFS pool:"
read RPOOL
echo "ZFS pool set to $RPOOL"
echo "Set a username for the new system:"
read USERNAME
echo "Username set to $USERNAME"
#echo "Set a password for the new system/user:"
#read PASSWORD
ifconfig -a
echo "Type the name of your network interface:"
read IFACE
echo "Network interface set to $IFACE"

sgdisk -z /dev/$DISKID
sleep 5

if [[ "$MBRBOOT" == "MBR" ]]
  then
    sgdisk -g -a1 -n2:34:2047 -t2:EF02 /dev/$DISKID &&
  sleep 2
  fi
if [[ "$GPTBOOT" == "GPT" ]]
  then
    sgdisk -g -n3:1M:+512M -t3:EF00 /dev/$DISKID &&
   sleep 2
  fi
sgdisk -g -n9:-8M:0 -t9:BF07 /dev/$DISKID &&
sleep 2
sgdisk -g -n1:0:0 -t1:BF01 /dev/$DISKID &&
sleep 2
sudo zpool destroy $RPOOL
zpool create -f \
	-O atime=off \
	-O canmount=off \
	-O compression=lz4 \
	-O normalization=formD \
	-O mountpoint=/ \
	-R /mnt \
$RPOOL /dev/${DISKID}1
sleep 2

zfs create -o canmount=noauto -o mountpoint=/ $RPOOL/ROOT/ubuntu
zfs mount $RPOOL/ROOT/ubuntu
zfs create                 -o setuid=off              $RPOOL/home
zfs create -o mountpoint=/root                        $RPOOL/home/root
zfs create -o canmount=off -o setuid=off  -o exec=off $RPOOL/var
zfs create -o com.sun:auto-snapshot=false             $RPOOL/var/cache
zfs create                                            $RPOOL/var/log
zfs create                                            $RPOOL/var/spool
zfs create -o com.sun:auto-snapshot=false -o exec=on  $RPOOL/var/tmp


chmod 1777 /mnt/var/tmp

#3.4 Install the minimal system:
debootstrap xenial /mnt
zfs set devices=off $RPOOL
sudo zfs list

echo $RPOOL > /mnt/etc/hostname
echo 127.0.1.1       $RPOOL >> /mnt/etc/hosts
echo auto $IFACE >> /mnt/etc/network/interfaces.d/$IFACE
echo iface $IFACE inet dhcp >> /mnt/etc/network/interfaces.d/$IFACE
mount --rbind /dev  /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys  /mnt/sys &&

chroot /mnt /bin/bash -x <<'EOCHROOT'

cat >> /etc/apt/sources.list << EOLIST
deb http://archive.ubuntu.com/ubuntu xenial main universe restricted multiverse
deb-src http://archive.ubuntu.com/ubuntu xenial main universe restricted multiverse
deb http://security.ubuntu.com/ubuntu xenial-security main universe restricted multiverse
deb-src http://security.ubuntu.com/ubuntu xenial-security main universe restricted multiverse
deb http://archive.ubuntu.com/ubuntu xenial-updates main universe restricted multiverse
deb-src http://archive.ubuntu.com/ubuntu xenial-updates main universe restricted multiverse
EOLIST

ln -s /proc/self/mounts /etc/mtab &&
apt update &&
locale-gen en_US.UTF-8 &&
echo 'LANG="en_US.UTF-8"' > /etc/default/locale &&
dpkg-reconfigure tzdata &&
apt install --yes --no-install-recommends linux-image-generic wget nano &&
apt install --yes zfs-initramfs &&
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
if [[ "$MBRBOOT" == "MBR" ]]
  then
  apt install --yes grub-pc &&
  sleep 2
fi
# addgroup --system sambashare
echo -e "root:$PASSWORD" | chpasswd

passwd
zfs set mountpoint=legacy $RPOOL/var/log
zfs set mountpoint=legacy $RPOOL/var/tmp
cat >> /etc/fstab << EOF
rpool/var/log /var/log zfs defaults 0 0
rpool/var/tmp /var/tmp zfs defaults 0 0
EOF
ln -s /dev/$DISKID /dev/${DISKID}3
grub-probe /
update-initramfs -c -k all
update-grub
if [[ "$GPTBOOT" == "GPT" ]]
  then
  grub-install --target=x86_64-efi --efi-directory=/boot/efi \
  --bootloader-id=ubuntu --recheck --no-floppy &&
  sleep 4
  fi
if [[ "$MBRBOOT" == "MBR" ]]
  then
  grub-install /dev/$DISKID &&
  sleep 4
fi
ls /boot/grub/*/zfs.mod
sed -i -e 's/GRUB_HIDDEN_TIMEOUT=0/#GRUB_HIDDEN_TIMEOUT=5/g'
sed -i -e 's/"quiet splash"/""/g'
sed -i -e 's/#GRUB_TERMINAL=console/GRUB_TERMINAL=console/g'
update-grub
zfs snapshot $RPOOL/ROOT/ubuntu@install
#zfs create precision/home/$USERNAME
#adduser $USERNAME
#cp -a /etc/skel/.[!.]* /home/$USERNAME
#chown -R $USERNAME:$USERNAME /home/$USERNAME
#usermod -a -G adm,cdrom,dip,lpadmin,plugdev,sambashare,sudo $USERNAME
#echo -e "$USERNAME:$PASSWORD" | chpasswd

zfs create -V 8G -b $(getconf PAGESIZE) -o compression=zle -o logbias=throughput -o sync=always -o primarycache=metadata -o secondarycache=none -o com.sun:auto-snapshot=false $RPOOL/swap &&
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
#apt install --yes $DISTRO 
apt install --yes ubuntu-minimal --no-install-recommends linux-image-generic  zfs-initramfs cryptsetup grub-efi

#while true
#do
#    read -r -p 'Disable root password (y/n)? ' choice
#    case "$choice" in
#      n|N) break;;
#      y|Y) usermod -p '*' root &&
#           break;;
#      *) echo 'Response not valid';;
#    esac
#done
echo 'Exiting chroot.'
EOCHROOT
while true
do
    read -r -p "Would you like to unmount $RPOOL now (y/n)? " choice
    case "$choice" in
      n|N) break;;
      y|Y) mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {} && zpool export $RPOOL &&
           break;;
      *) echo 'Response not valid';;
    esac
done
while true
do
    read -r -p 'Would you like to reboot now (y/n)? ' choice
    case "$choice" in
      n|N) break;;
      y|Y) reboot;;
      *) echo 'Response not valid';;
    esac
done
