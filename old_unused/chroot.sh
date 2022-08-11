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
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}        ${GREEN_LIGHT}fstab creation${NORMAL}         ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

  echo -e -n "\nExporting variables that will be used for fstab...\n"
  export UEFI_UUID=$(blkid -s UUID -o value "$boot_partition")
  export LUKS_UUID=$(blkid -s UUID -o value "$encrypted_partition")
  export ROOT_UUID=$(blkid -s UUID -o value "$final_drive")
  
  echo -e -n "\nWriting fstab...\n\n"
  sed -i '/tmpfs/d' /etc/fstab

cat << EOF >> /etc/fstab

# root subvolume
UUID=$ROOT_UUID / btrfs $BTRFS_OPT,subvol=@ 0 1

# home subvolume
UUID=$ROOT_UUID /home btrfs $BTRFS_OPT,subvol=@home 0 2

# root snapshots subvolume, uncomment the following line after creating a config for root [/] in snapper
#UUID=$ROOT_UUID /.snapshots btrfs $BTRFS_OPT,subvol=@snapshots 0 2

# EFI partition
UUID=$UEFI_UUID /boot/efi vfat defaults,noatime 0 2

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

$encrypted_name UUID=$LUKS_UUID /boot/volume.key luks
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
  echo -e "add_dracutmodules+=\" crypt btrfs lvm resume \"" >> /etc/dracut.conf.d/20-addmodules.conf
  echo -e "tmpdir=/tmp" >> /etc/dracut.conf.d/30-tmpfs.conf

  echo -e -n "\nGenerating new dracut initramfs...\n\n"
  read -n 1 -r -p "[Press any key to continue...]" key
  echo
  dracut --regenerate-all --force --hostonly

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

  while true ; do
    echo -e -n "\nSelect a ${BLUE_LIGHT}bootloader-id${NORMAL} that will be used for grub install: "
    read -r bootloader_id
    if [[ -z "$bootloader_id" ]] ; then
      echo -e -n "\nPlease enter a valid bootloader-id.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
    else
      while true ; do
        echo -e -n "\nYou entered: ${BLUE_LIGHT}$bootloader_id${NORMAL}.\n\n"
        read -n 1 -r -p "Is this the desired bootloader-id? (y/n): " yn
        if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
          echo -e -n "\n\nInstalling GRUB on ${BLUE_LIGHT}/boot/efi${NORMAL} partition with ${BLUE_LIGHT}$bootloader_id${NORMAL} as bootloader-id...\n\n"
          grub-install --target=x86_64-efi --boot-directory=/boot --efi-directory=/boot/efi --bootloader-id="$bootloader_id" --recheck
          break 2
        elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
          echo -e -n "\n\nPlease select another bootloader-id.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          break
        else
          echo -e -n "\nPlease answer y or n.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
        fi
      done
    fi
  done

  if [[ "$lvm_yn" == "y" ]] || [[ "$lvm_yn" == "Y" ]] ; then
    echo -e -n "\nEnabling SSD trim for LVM...\n"
    sed -i 's/issue_discards = 0/issue_discards = 1/' /etc/lvm/lvm.conf
  fi

  echo
  read -n 1 -r -p "[Press any key to continue...]" key
  clear

}

function header_cs {
    echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
    echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
    echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
    echo -e -n "${GREEN_DARK}#######${NORMAL}       ${GREEN_LIGHT}SwapFile creation${NORMAL}       ${GREEN_DARK}#${NORMAL}\n"
    echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
}

function create_swapfile {

  while true ; do

    header_cs

    echo -e -n "\nDo you want to create a ${BLUE_LIGHT}swapfile${NORMAL} in ${BLUE_LIGHT}/var/swap/${NORMAL} btrfs subvolume?\nThis will also enable ${BLUE_LIGHT}zswap${NORMAL}, a cache in RAM for swap.\nA swapfile is needed if you plan to use hibernation (y/n): "
    read -n 1 -r yn
  
    if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then

      ram_size=$(free -g --si | awk -F " " 'FNR == 2 {print $2}')

      while true ; do
        clear
        header_cs
        echo -e -n "\nYour system has ${BLUE_LIGHT}${ram_size}GB${NORMAL} of RAM.\n"
        echo -e -n "\nPress [ENTER] to create a swapfile of the same dimensions or choose the desired size in GB (only numbers): "
        read -r swap_size

        if [[ "$swap_size" == "" ]] || [[ "$swap_size" -gt "0" ]] ; then
          if [[ "$swap_size" == "" ]] ; then
            swap_size=$ram_size
          fi
          echo -e -n "\nA swapfile of ${BLUE_LIGHT}${swap_size}GB${NORMAL} will be created in ${BLUE_LIGHT}/var/swap/${NORMAL} btrfs subvolume...\n\n"
          btrfs subvolume create /var/swap
          truncate -s 0 /var/swap/swapfile
          chattr +C /var/swap/swapfile
          chmod 600 /var/swap/swapfile
          dd if=/dev/zero of=/var/swap/swapfile bs=1G count="$swap_size" status=progress
          mkswap /var/swap/swapfile
          swapon /var/swap/swapfile
          gcc -O2 "$HOME"/btrfs_map_physical.c -o "$HOME"/btrfs_map_physical
          RESUME_OFFSET=$(($("$HOME"/btrfs_map_physical /var/swap/swapfile | awk -F " " 'FNR == 2 {print $NF}')/$(getconf PAGESIZE)))
          sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET&/" /etc/default/grub

cat << EOF >> /etc/fstab

# SwapFile
/var/swap/swapfile none swap defaults 0 0
EOF

          echo -e -n "\nEnabling zswap...\n"
          echo "add_drivers+=\" lz4hc lz4hc_compress \"" >> /etc/dracut.conf.d/40-add_lz4hc_drivers.conf
          echo -e -n "\nRegenerating dracut initramfs...\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          echo
          dracut --regenerate-all --force --hostonly
          sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ zswap.enabled=1 zswap.max_pool_percent=25 zswap.compressor=lz4hc zswap.zpool=z3fold&/" /etc/default/grub
          echo -e -n "\nUpdating grub...\n\n"
          update-grub
          swapoff --all
          echo -e -n "\nSwapfile successfully created and zswap successfully enabled.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          break 2

        else
          echo -e -n "\nPlease enter a valid value.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
        fi

      done

    elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
      echo -e -n "\n\nNo swapfile created.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
      break
    
    else
      echo -e -n "\nPlease answer y or n.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
    fi
  
  done

}

function header_fc {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}         ${GREEN_LIGHT}Final touches${NORMAL}         ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function finish_chroot {

  header_fc
  echo -e -n "\nSetting the ${BLUE_LIGHT}timezone${NORMAL} in /etc/rc.conf.\n\nPress any key to list all the timezones.\nMove with arrow keys and press \"q\" to exit the list."
  read -n 1 -r key
  echo
  awk '/^Z/ { print $2 }; /^L/ { print $3 }' /usr/share/zoneinfo/tzdata.zi | less --RAW-CONTROL-CHARS --no-init
  while true ; do
    echo -e -n "\nType the timezone you want to set and press [ENTER] (i.e. America/New_York): "
    read -r user_timezone
    if [[ ! -f /usr/share/zoneinfo/"$user_timezone" ]] ; then
      echo -e "\nEnter a valid timezone.\n"
      read -n 1 -r -p "[Press any key to continue...]" key
    else
      sed -i "/#TIMEZONE=/s|.*|TIMEZONE=\"$user_timezone\"|" /etc/rc.conf
      echo -e -n "\nTimezone set to: ${BLUE_LIGHT}$user_timezone${NORMAL}.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
      break
    fi
  done

  header_fc
  if [[ -n "$user_keyboard_layout" ]] ; then
    echo -e -n "\nSetting ${BLUE_LIGHT}$user_keyboard_layout${NORMAL} keyboard layout in /etc/rc.conf...\n\n"
    sed -i "/#KEYMAP=/s/.*/KEYMAP=\"$user_keyboard_layout\"/" /etc/rc.conf
    read -n 1 -r -p "[Press any key to continue...]" key
    clear
  else
    echo -e -n "\nSetting ${BLUE_LIGHT}keyboard layout${NORMAL} in /etc/rc.conf.\n\nPress any key to list all the keyboard layouts.\nMove with arrow keys and press \"q\" to exit the list."
    read -n 1 -r key
    echo
    find /usr/share/kbd/keymaps/ -type f -iname "*.map.gz" -printf "${BLUE_LIGHT_FIND}%f\0${NORMAL_FIND}\n" | sed -e 's/\..*$//' | sort |less --RAW-CONTROL-CHARS --no-init
    while true ; do
      echo -e -n "\nType the keyboard layout you want to set and press [ENTER]: "
      read -r user_keyboard_layout
      if [[ -z "$user_keyboard_layout" ]] || ! loadkeys "$user_keyboard_layout" 2> /dev/null ; then
        echo -e -n "\nPlease select a valid keyboard layout.\n\n"
        read -n 1 -r -p "[Press any key to continue...]" key
      else
        sed -i "/#KEYMAP=/s/.*/KEYMAP=\"$user_keyboard_layout\"/" /etc/rc.conf
        echo -e -n "\nKeyboard layout set to: ${BLUE_LIGHT}$user_keyboard_layout${NORMAL}.\n\n"
        read -n 1 -r -p "[Press any key to continue...]" key
        clear
        break
      fi
    done
  fi

  if [[ "$ARCH" == "x86_64" ]] ; then
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
        while true ; do
          user_locale_pre=$(sed -n "${user_locale_line_number}"p /etc/default/libc-locales)
          user_locale_uncommented=$(echo "${user_locale_pre//#}")
          user_locale=$(echo "${user_locale_uncommented%%[[:space:]]*}")
          echo -e -n "\nYou choose line ${BLUE_LIGHT}$user_locale_line_number${NORMAL} that cointains locale ${BLUE_LIGHT}$user_locale${NORMAL}.\n\n"
          read -n 1 -r -p "Is this correct? (y/n): " yn
          if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
            echo -e -n "\n\nUncommenting line ${BLUE_LIGHT}$user_locale_line_number${NORMAL} that contains locale ${BLUE_LIGHT}$user_locale${NORMAL}...\n"
            sed -i "$user_locale_line_number s/^#//" /etc/default/libc-locales
            echo -e -n "\nWriting locale ${BLUE_LIGHT}$user_locale${NORMAL} to /etc/locale.conf...\n\n"
            sed -i "/LANG=/s/.*/LANG=$user_locale/" /etc/locale.conf
            read -n 1 -r -p "[Press any key to continue...]" key
            clear
            break 2
          elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
            echo -e -n "\n\nPlease select another locale.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key
            break
          else
            echo -e -n "\nPlease answer y or n.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key
          fi
        done
      fi
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

  while true ; do
    header_fc
    echo -e -n "\nListing all the available shells:\n\n"
    chsh --list-shells
    echo -e -n "\nWhich ${BLUE_LIGHT}shell${NORMAL} do you want to set for ${BLUE_LIGHT}root${NORMAL} user?\nPlease enter the full path (i.e. /bin/sh): "
    read -r set_shell
    if [[ ! -x "$set_shell" ]] ; then
      echo -e -n "\nPlease enter a valid shell.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
    else
      while true ; do
        echo -e -n "\nYou entered: ${BLUE_LIGHT}$set_shell${NORMAL}.\n\n"
        read -n 1 -r -p "Is this the desired shell? (y/n): " yn
        if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
          echo
          echo
          chsh --shell "$set_shell"
          echo -e -n "\nDefault shell successfully changed.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          break 2
        elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
          echo -e -n "\n\nPlease select another shell.\n\n"
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

  echo -e -n "\nEnabling grub snapshot service at first boot...\n"
  ln -s /etc/sv/grub-btrfs /etc/runit/runsvdir/default/

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
create_swapfile
finish_chroot
exit 0
