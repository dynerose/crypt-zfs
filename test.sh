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

echo '2 create zfs'
sudo zpool destroy $RPOOL
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

