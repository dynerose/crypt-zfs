#!/bin/bash
# test.sh

echo '1 Install neccessary packages:'
# sudo apt-add-repository universe
# sudo apt update
# sudo apt install zfsutils-linux zfs-initramfs cryptsetup debootstrap dosfstools gdisk mdadm mc nano -y

echo "WARNING!  This script could wipe out all your data, or worse!  I am not responsible for your decisions.  Carefully enter the ID of the disk YOU WANT TO DESTROY in the next step to ensure no data is accidentally lost.  Press Enter to continue."
read DISCLAIMER
mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {}
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
echo "Set a password for the new system/user:"
read PASSWORD
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

echo '2 create zfs'
sudo zpool destroy -f $RPOOL
zpool create -o ashift=12 \
      -O atime=off -O canmount=off -O compression=lz4 -O normalization=formD \
      -O mountpoint=/ -R /mnt \
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

"echo '3.Install the minimal system:'
#debootstrap xenial /mnt
#zfs set devices=off $RPOOL
#sudo zfs list

echo $RPOOL > /mnt/etc/hostname
echo 127.0.1.1       $RPOOL >> /mnt/etc/hosts
echo auto $IFACE >> /mnt/etc/network/interfaces.d/$IFACE
echo iface $IFACE inet dhcp >> /mnt/etc/network/interfaces.d/$IFACE
mount --rbind /dev  /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys  /mnt/sys &&

chroot /mnt /bin/bash -x <<'EOCHROOT'
# chroot /mnt /bin/bash --login
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
apt install --yes ubuntu-minimal zfsutils-linux &&

# apt install --yes ubuntu-minimal
# apt install --yes openssh-server cryptsetup grub-efi
# apt install --yes zfsutils-linux grub-pc dosfstools gdisk

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
sudo adduser $USERNAME --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password
echo "$USERNAME:$PASSWORD" | sudo chpasswd

