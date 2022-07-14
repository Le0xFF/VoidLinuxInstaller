#! /bin/bash

function set_root {
  
  echo -e -n "\nSetting root password:\n\n"
  passwd root
  
  echo -e -n "\nSetting root permissions...\n"
  chown root:root /
  chmod 755 /
    
}

function edit_fstab {

  echo -e -n "\nExporting variables that will be used for fstab...\n"
  export UEFI_UUID=$(blkid -s UUID -o value ${boot_partition})
  export LUKS_UUID=$(blkid -s UUID -o value ${encrypted_partition})
  export ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/${vg_name}-${lv_root_name})
  export HOME_UUID=$(blkid -s UUID -o value /dev/mapper/${vg_name}-${lv_home_name})
  
  echo -e -n "\nWriting fstab...\n"
  sed -i '/tmpfs/d' /etc/fstab
cat << EOF >> /etc/fstab
UUID=$ROOT_UUID / btrfs $BTRFS_OPT,subvol=@ 0 1
UUID=$HOME_UUID /home btrfs $BTRFS_OPT,subvol=@home 0 2
UUID=$ROOT_UUID /.snapshots btrfs $BTRFS_OPT,subvol=@snapshots 0 2
UUID=$UEFI_UUID /boot/efi vfat defaults,noatime 0 2
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
EOF

}

function generate_random_key {

  echo -e -n "\nGenerate random key to avoid typing password twice at boot...\n"
  dd bs=512 count=4 if=/dev/random of=/boot/volume.key
  
  echo -e -n "\nRandom key generated, unlocking the encrypted partition...\n"
  cryptsetup luksAddKey "${encrypted_partition}" /boot/volume.key
  chmod 000 /boot/volume.key
  chmod -R g-rwx,o-rwx /boot

  echo -e -n "\nAdding random key to /etc/crypttab...\n"
cat << EOF >> /etc/crypttab
$encrypted_name UUID=$LUKS_UUID /boot/volume.key luks
EOF
  
}

function generate_dracut_conf {

  echo -e -n "\nAdding random key to dracut configuration...\n"
cat << EOF >> /etc/dracut.conf.d/10-crypt.conf
install_items+=" /boot/volume.key /etc/crypttab "
EOF

  echo -e -n "\nAdding other needed dracut configuration files...\n"
  echo -e "hostonly=yes\nhostonly_cmdline=yes" >> /etc/dracut.conf.d/00-hostonly.conf
  echo -e "add_dracutmodules+=\" crypt btrfs lvm resume \"" >> /etc/dracut.conf.d/20-addmodules.conf
  echo -e "tmpdir=/tmp" >> /etc/dracut.conf.d/30-tmpfs.conf

  echo -e -n "\nGenerating new dracut initramfs...\n"
  dracut --force --hostonly --kver $(ls /usr/lib/modules/)

}

function install_grub {

  echo -e -n "\nEnabling CRYPTODISK in GRUB...\n"
cat << EOF >> /etc/default/grub
GRUB_ENABLE_CRYPTODISK=y
EOF

  sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ rd.auto=1 rd.luks.name=$LUKS_UUID=$encrypted_name rd.luks.allow-discards=$LUKS_UUID&/" /etc/default/grub

  if ! cat /proc/mounts | grep efivar &> /dev/null ; then
    echo -e -n "\nMounting efivarfs...\n"
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars/
  fi
  
  echo -e -n "\nInstalling GRUB on "${user_drive}" with \"VoidLinux\" as bootloader-id...\n\n"
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=VoidLinux --boot-directory=/boot --recheck

  echo -e -n "\nEnabling SSD trim...\n"
  sed -i 's/issue_discards = 0/issue_discards = 1/' /etc/lvm/lvm.conf

}

function enabling_services {

  echo -e -n "\nEnabling internet service at first boot...\n"
  ln -s /etc/sv/dbus /etc/runit/runsvdir/default/
  ln -s /etc/sv/NetworkManager /etc/runit/runsvdir/default/
  
}

set_root
edit_fstab
generate_random_key
generate_dracut_conf
install_grub
enabling_services

echo -e -n "\nReconfiguring every package...\n"
xbps-reconfigure -fa

echo -e -n "\nEverything's done, exiting chroot...\n"
