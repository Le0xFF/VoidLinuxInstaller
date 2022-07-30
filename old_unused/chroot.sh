#! /bin/bash

function set_root {

  clear
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}     ${GREEN_LIGHT}Setting root password${NORMAL}     ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  
  echo -e -n "\nSetting root password:\n\n"
  passwd root
  
  echo -e -n "\nSetting root permissions...\n\n"
  chown root:root /
  chmod 755 /

  read -n 1 -r -p "[Press any key to continue...]" key
  clear
    
}

function edit_fstab {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################\${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}        ${GREEN_LIGHT}fstab creation${NORMAL}         ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################\${NORMAL}\n"

  echo -e -n "\nExporting variables that will be used for fstab...\n"
  export UEFI_UUID=$(blkid -s UUID -o value "$boot_partition")
  export LUKS_UUID=$(blkid -s UUID -o value "$encrypted_partition")
  if [[ "$lvm_yn" == "y" ]] || [[ "$lvm_yn" == "Y" ]] ; then
    export ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/"$vg_name"-"$lv_root_name")
  elif [[ "$lvm_yn" == "n" ]] || [[ "$lvm_yn" == "N" ]] ; then
    export ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/"$encrypted_name")
  fi
  
  echo -e -n "\nWriting fstab...\n\n"
  sed -i '/tmpfs/d' /etc/fstab

cat << EOF >> /etc/fstab

# root subvolume
UUID=\$ROOT_UUID / btrfs \$BTRFS_OPT,subvol=@ 0 1

# home subvolume
UUID=\$ROOT_UUID /home btrfs \$BTRFS_OPT,subvol=@home 0 2

# root snapshots subvolume, uncomment the following line after creating a config for root [/] in snapper
#UUID=\$ROOT_UUID /.snapshots btrfs \$BTRFS_OPT,subvol=@snapshots 0 2

# EFI partition
UUID=\$UEFI_UUID /boot/efi vfat defaults,noatime 0 2

# TMPfs
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
EOF

  read -n 1 -r -p "[Press any key to continue...]" key
  clear

}

function generate_random_key {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}     ${GREEN_LIGHT}Random key generation${NORMAL}     ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

  echo -e -n "\nGenerate random key to avoid typing password twice at boot...\n\n"
  dd bs=512 count=4 if=/dev/random of=/boot/volume.key
  
  echo -e -n "\nRandom key generated, unlocking the encrypted partition...\n"
  cryptsetup luksAddKey "$encrypted_partition" /boot/volume.key
  chmod 000 /boot/volume.key
  chmod -R g-rwx,o-rwx /boot

  echo -e -n "\nAdding random key to /etc/crypttab...\n\n"
cat << EOF >> /etc/crypttab

\$encrypted_name UUID=\$LUKS_UUID /boot/volume.key luks
EOF

  read -n 1 -r -p "[Press any key to continue...]" key
  clear
  
}

function generate_dracut_conf {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}     ${GREEN_LIGHT}Dracut configuration${NORMAL}      ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

  echo -e -n "\nAdding random key to dracut configuration...\n"
cat << EOF >> /etc/dracut.conf.d/10-crypt.conf
install_items+=" /boot/volume.key /etc/crypttab "
EOF

  echo -e -n "\nAdding other needed dracut configuration files...\n"
  echo -e "hostonly=yes\nhostonly_cmdline=yes" >> /etc/dracut.conf.d/00-hostonly.conf
  echo -e "add_dracutmodules+=\" crypt btrfs lvm \"" >> /etc/dracut.conf.d/20-addmodules.conf
  echo -e "tmpdir=/tmp" >> /etc/dracut.conf.d/30-tmpfs.conf

  echo -e -n "\nGenerating new dracut initramfs...\n\n"
  read -n 1 -r -p "[Press any key to continue...]" key
  echo
  dracut --force --hostonly --kver $(ls /usr/lib/modules/)

  echo
  read -n 1 -r -p "[Press any key to continue...]" key
  clear

}

function header_ig {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}       ${GREEN_LIGHT}GRUB installation${NORMAL}       ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  
}

function install_grub {

  header_ig

  echo -e -n "\nEnabling CRYPTODISK in GRUB...\n"
cat << EOF >> /etc/default/grub

GRUB_ENABLE_CRYPTODISK=y
EOF

  sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ rd.auto=1 rd.luks.name=$LUKS_UUID=$encrypted_name rd.luks.allow-discards=$LUKS_UUID&/" /etc/default/grub

  if ! grep -q efivar /proc/mounts ; then
    echo -e -n "\nMounting efivarfs...\n"
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars/
  fi

  echo -e -n "\nInstalling GRUB on ${BLUE_LIGHT}/boot/efi${NORMAL} partition with ${BLUE_LIGHT}VoidLinux${NORMAL} as bootloader-id...\n\n"
  grub-install --target=x86_64-efi --boot-directory=/boot --efi-directory=/boot/efi --bootloader-id=VoidLinux --recheck

  if [[ "$lvm_yn" == "y" ]] || [[ "$lvm_yn" == "Y" ]] ; then
    echo -e -n "\nEnabling SSD trim for LVM...\n"
    sed -i 's/issue_discards = 0/issue_discards = 1/' /etc/lvm/lvm.conf
  fi

  echo
  read -n 1 -r -p "[Press any key to continue...]" key
  clear

}

function header_fc {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}         ${GREEN_LIGHT}Final touches${NORMAL}         ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function finish_chroot {

  while true ; do
    header_fc
    echo -e -n "\nSetting the ${BLUE_LIGHT}timezone${NORMAL} in /etc/rc.conf.\n\nPress any key to list all the timezones.\nMove with arrow keys and press \"q\" to exit the list."
    read -n 1 -r key
    echo
    awk '/^Z/ { print $2 }; /^L/ { print $3 }' /usr/share/zoneinfo/tzdata.zi | less --RAW-CONTROL-CHARS --no-init
    while true ; do
      echo -e -n "\nType the timezone you want to set and press [ENTER] (i.e. America/New_York): "
      read -r user_timezone
      if [[ ! -e /usr/share/zoneinfo/"$user_timezone" ]] ; then
        echo -e "\nEnter a valid timezone.\n"
        read -n 1 -r -p "[Press any key to continue...]" key
        break
      else
        sed -i "/#TIMEZONE=/s|.*|TIMEZONE=\"$user_timezone\"|" /etc/rc.conf
        echo -e -n "\nTimezone set to: ${BLUE_LIGHT}$user_timezone${NORMAL}.\n\n"
        read -n 1 -r -p "[Press any key to continue...]" key
        clear
        break 2
      fi
    done
  done

  while true ; do
    header_fc
    if [[ -n "$user_keyboard_layout" ]] ; then
      echo -e -n "\nSetting ${BLUE_LIGHT}$user_keyboard_layout${NORMAL} keyboard layout in /etc/rc.conf...\n\n"
      sed -i "/#KEYMAP=/s/.*/KEYMAP=\"$user_keyboard_layout\"/" /etc/rc.conf
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
      break
    else
      echo -e -n "\nSetting ${BLUE_LIGHT}keyboard layout${NORMAL} in /etc/rc.conf.\n\nPress any key to list all the keyboard layouts.\nMove with arrow keys and press \"q\" to exit the list."
      read -n 1 -r key
      echo
      ls --color=always -R /usr/share/kbd/keymaps/ | grep "\.map.gz" | sed -e 's/\..*$//' | less --RAW-CONTROL-CHARS --no-init
      while true ; do
        echo -e -n "\nType the keyboard layout you want to set and press [ENTER]: "
        read -r user_keyboard_layout
        if [[ -z "$user_keyboard_layout" ]] || ! loadkeys "$user_keyboard_layout" 2> /dev/null ; then
          echo -e -n "\nPlease select a valid keyboard layout.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
        else
          sed -i "/#KEYMAP=/s/.*/KEYMAP=\"$user_keyboard_layout\"/" /etc/rc.conf
          echo -e -n "\nKeyboard layout set to: ${BLUE_LIGHT}$user_timezone${NORMAL}.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          break 2
        fi
      done
    fi
  done

  if [[ "$ARCH" == "x86_64" ]] ; then
    while true ; do
      header_fc
      echo -e -n "\nSetting the ${BLUE_LIGHT}locale${NORMAL} in /etc/default/libc-locales.\n\nPress any key to print all the available locales.\n\nKeep in mind the ${BLUE_LIGHT}one line number${NORMAL} you need because that line will be uncommented.\n\nMove with arrow keys and press \"q\" to exit the list."
      read -n 1 -r key
      echo
      less --LINE-NUMBERS --RAW-CONTROL-CHARS --no-init /etc/default/libc-locales
      while true ; do
        echo -e -n "\nType only ${BLUE_LIGHT}one line number${NORMAL} you want to uncomment to set your locale and and press [ENTER]: "
        read -r user_locale_line_number
        if [[ -z "$user_locale_line_number" ]] ; then
          echo -e "\nEnter a valid line-number.\n"
          read -n 1 -r -p "[Press any key to continue...]" key
        else
          user_locale_pre=$(sed -n ${user_locale_line_number}p /etc/default/libc-locales)
          user_locale_uncommented=$(echo ${user_locale_pre//#})
          user_locale=$(echo ${user_locale_uncommented%%[[:space:]]*})
          echo -e -n "\nUncommenting line ${BLUE_LIGHT}$user_locale_line_number${NORMAL} that contains locale ${BLUE_LIGHT}$user_locale${NORMAL}...\n"
          sed -i "$user_locale_line_number s/^#//" /etc/default/libc-locales
          echo -e -n "\nWriting locale ${BLUE_LIGHT}$user_locale${NORMAL} to /etc/locale.conf...\n\n"
          sed -i "/LANG=/s/.*/LANG=$user_locale/" /etc/locale.conf
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          break 2
        fi
      done
    done
  fi

  while true ; do
    header_fc
    echo -e -n "\nSelect a ${BLUE_LIGHT}hostname${NORMAL} for your system: "
    read -r hostname
    if [[ -z "$hostname" ]] ; then
      echo -e -n "\nPlease enter a valid hostname.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
    else
      while true ; do
        echo -e -n "\nYou entered: ${BLUE_LIGHT}$hostname${NORMAL}.\n\n"
        read -n 1 -r -p "Is this the desired hostname? (y/n): " yn
        if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
          set +o noclobber
          echo "$hostname" > /etc/hostname
          set -o noclobber
          echo -e -n "\n\nHostname successfully set.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          break 2
        elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
          echo -e -n "\n\nPlease select another hostname.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          break
        else
          echo -e -n "\nPlease answer y or n.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
        fi
      done
    fi
  done

  header_fc

  echo -e -n "\nEnabling internet service at first boot...\n"
  ln -s /etc/sv/dbus /etc/runit/runsvdir/default/
  ln -s /etc/sv/NetworkManager /etc/runit/runsvdir/default/

  echo -e -n "\nReconfiguring every package...\n\n"
  read -n 1 -r -p "[Press any key to continue...]" key
  echo
  xbps-reconfigure -fa

  echo -e -n "\nEverything's done, exiting chroot...\n\n"

  read -n 1 -r -p "[Press any key to continue...]" key
  clear

}

set_root
edit_fstab
generate_random_key
generate_dracut_conf
install_grub
finish_chroot
exit 0
