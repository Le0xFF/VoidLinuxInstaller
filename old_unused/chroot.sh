#! /bin/bash

# Variables

bootloader_id=''
bootloader=''
newuser_yn='n'

# Functions

function press_any_key_to_continue {

  echo -e -n "${BLACK_FG_WHITE_BG}[Press any key to continue...]${NORMAL}"
  read -n 1 -r _key

}

# Source: https://www.reddit.com/r/voidlinux/comments/jlkv1j/xs_quick_install_tool_for_void_linux/
function xs {

  xpkg -a |
    fzf -m --preview 'xq {1}' --preview-window=right:66%:wrap |
    xargs -ro xi

  press_any_key_to_continue

}

function header_ic {
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}     ${GREEN_LIGHT}Initial configuration${NORMAL}     ${GREEN_LIGHT}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
}

function initial_configuration {
  clear
  header_ic

  # Root password
  echo -e -n "\nSetting ${BLUE_LIGHT}root password${NORMAL}:\n"
  while true; do
    echo
    if passwd root; then
      break
    else
      echo -e -n "\n${RED_LIGHT}Something went wrong, please try again.${NORMAL}\n\n"
      press_any_key_to_continue
      echo
    fi
  done

  echo -e -n "\nSetting root permissions...\n"
  chown root:root /
  chmod 755 /

  echo -e -n "\nEnabling wheel group to use sudo...\n"
  echo "%wheel ALL=(ALL) ALL" >/etc/sudoers.d/10-wheel

  echo -e -n "\nExporting variables that will be used for fstab...\n"
  export LUKS_UUID=$(blkid -s UUID -o value "$root_partition")
  export ROOT_UUID=$(blkid -s UUID -o value "$final_drive")

  echo -e -n "\nWriting fstab...\n"
  sed -i '/tmpfs/d' /etc/fstab

  cat <<EOF >>/etc/fstab

# Root subvolume
UUID=$ROOT_UUID / btrfs $BTRFS_OPT,subvol=@ 0 1

# Home subvolume
UUID=$ROOT_UUID /home btrfs $BTRFS_OPT,subvol=@home 0 2

# Snapshots subvolume, uncomment the following line after creating a config for root [/] in snapper
#UUID=$ROOT_UUID /.snapshots btrfs $BTRFS_OPT,subvol=@snapshots 0 2

# Some applications don't like to have /var/log folders as read only.
# Log folders, to allow booting snapshots with rd.live.overlay.overlayfs=1
UUID=$ROOT_UUID /var/log btrfs $BTRFS_OPT,subvol=@/var/log 0 2

# TMPfs
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
EOF

  echo -e -n "\nEnabling internet service at first boot...\n"
  ln -s /etc/sv/dbus /etc/runit/runsvdir/default/
  ln -s /etc/sv/NetworkManager /etc/runit/runsvdir/default/

  echo -e -n "\nAdding needed dracut configuration files...\n"
  echo -e "hostonly=yes\nhostonly_cmdline=yes" >>/etc/dracut.conf.d/00-hostonly.conf
  echo -e "add_dracutmodules+=\" crypt btrfs lvm resume \"" >>/etc/dracut.conf.d/20-addmodules.conf
  echo -e "tmpdir=/tmp" >>/etc/dracut.conf.d/30-tmpfs.conf

  echo -e -n "\nGenerating new dracut initramfs...\n\n"
  press_any_key_to_continue
  echo
  dracut --regenerate-all --force --hostonly

  echo
  press_any_key_to_continue

  # Set timezone
  clear
  header_ic
  echo -e -n "\nSetting the ${BLUE_LIGHT}timezone${NORMAL} in /etc/rc.conf.\n"
  echo -e -n "\nPress any key to list all the timezones. Move with arrow keys and press \"q\" to exit the list."
  read -n 1 -r _key
  echo
  awk '/^Z/ { print $2 }; /^L/ { print $3 }' /usr/share/zoneinfo/tzdata.zi |
    less --RAW-CONTROL-CHARS --no-init
  while true; do
    echo -e -n "\nType the timezone you want to set and press [ENTER] (i.e. America/New_York): "
    read -r user_timezone
    if [[ ! -f /usr/share/zoneinfo/"$user_timezone" ]]; then
      echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
      press_any_key_to_continue
    else
      sed -i "/#TIMEZONE=/s|.*|TIMEZONE=\"$user_timezone\"|" /etc/rc.conf
      echo -e -n "\n${GREEN_LIGHT}Timezone set to: $user_timezone.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
      break
    fi
  done

  # Set keyboard layout
  clear
  header_ic
  if [[ -n "$user_keyboard_layout" ]]; then
    echo -e -n "\nSetting ${BLUE_LIGHT}$user_keyboard_layout${NORMAL} keyboard layout in /etc/rc.conf...\n"
    sed -i "/#KEYMAP=/s/.*/KEYMAP=\"$user_keyboard_layout\"/" /etc/rc.conf
    echo -e -n "\nSetting keymap in dracut configuration and regenerating initramfs...\n\n"
    echo -e "i18n_vars=\"/etc/rc.conf:KEYMAP\"\ni18n_install_all=\"no\"" >>/etc/dracut.conf.d/i18n.conf
    press_any_key_to_continue
    echo
    dracut --regenerate-all --force --hostonly
    echo
    press_any_key_to_continue
    clear
  else
    echo -e -n "\nSetting ${BLUE_LIGHT}keyboard layout${NORMAL} in /etc/rc.conf.\n\nPress any key to list all the keyboard layouts.\nMove with arrow keys and press \"q\" to exit the list."
    read -n 1 -r _key
    echo
    find /usr/share/kbd/keymaps/ -type f -iname "*.map.gz" -printf "${BLUE_LIGHT_FIND}%f\0${NORMAL_FIND}\n" |
      sed -e 's/\..*$//' |
      sort |
      less --RAW-CONTROL-CHARS --no-init
    while true; do
      echo -e -n "\nType the keyboard layout you want to set and press [ENTER]: "
      read -r user_keyboard_layout
      if [[ -z "$user_keyboard_layout" ]] || ! loadkeys "$user_keyboard_layout" 2>/dev/null; then
        echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
        press_any_key_to_continue
      else
        sed -i "/#KEYMAP=/s/.*/KEYMAP=\"$user_keyboard_layout\"/" /etc/rc.conf
        echo -e -n "\nKeyboard layout set to: ${BLUE_LIGHT}$user_keyboard_layout${NORMAL}.\n"
        echo -e -n "\nSetting keymap in dracut configuration and regenerating initramfs...\n\n"
        echo -e "i18n_vars=\"/etc/rc.conf:KEYMAP\"\ni18n_install_all=\"no\"" >>/etc/dracut.conf.d/i18n.conf
        press_any_key_to_continue
        echo
        dracut --regenerate-all --force --hostonly
        echo
        press_any_key_to_continue
        clear
        break
      fi
    done
  fi

  # Set hostname
  while true; do
    header_ic
    echo -e -n "\nSelect a ${BLUE_LIGHT}hostname${NORMAL} for your system: "
    read -r hostname
    if [[ -z "$hostname" ]]; then
      echo -e -n "\n${RED_LIGHT}Please enter a valid hostname.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
    else
      while true; do
        echo -e -n "\nYou entered: ${BLUE_LIGHT}$hostname${NORMAL}.\n\n"
        read -r -p "Is this the desired hostname? (y/n): " yn
        if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]]; then
          set +o noclobber
          echo "$hostname" >/etc/hostname
          set -o noclobber
          echo -e -n "\n${GREEN_LIGHT}Hostname successfully set.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
          break 2
        elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]]; then
          echo -e -n "\n${RED_LIGHT}Please select another hostname.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
          break
        else
          echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
          press_any_key_to_continue
        fi
      done
    fi
  done

  # Set locales for x86_64
  if [[ "$ARCH" == "x86_64" ]]; then
    header_ic
    echo -e -n "\nSetting the ${BLUE_LIGHT}locale${NORMAL} in /etc/default/libc-locales."
    echo -e -n "\n\nPress any key to print all the available locales.\n\nPlease remember the ${BLUE_LIGHT}line number${NORMAL} corresponding to the locale you want to enable.\n"
    echo -e -n "\nMove with arrow keys and press \"q\" to exit the list."
    read -n 1 -r _key
    echo
    less --LINE-NUMBERS --RAW-CONTROL-CHARS --no-init /etc/default/libc-locales
    while true; do
      echo -e -n "\nPlease type the ${BLUE_LIGHT}line number${NORMAL} corresponding to the locale you want to enable and press [ENTER]: "
      read -r user_locale_line_number
      if [[ -z "$user_locale_line_number" ]] || [[ "$user_locale_line_number" -lt "11" ]] || [[ "$user_locale_line_number" -gt "499" ]]; then
        echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
        press_any_key_to_continue
      else
        while true; do
          user_locale_pre=$(sed -n "${user_locale_line_number}"p /etc/default/libc-locales)
          user_locale_uncommented=$(echo "${user_locale_pre//#/}")
          user_locale=$(echo "${user_locale_uncommented%%[[:space:]]*}")
          echo -e -n "\nYou choose line ${BLUE_LIGHT}$user_locale_line_number${NORMAL} that cointains locale ${BLUE_LIGHT}$user_locale${NORMAL}.\n\n"
          read -r -p "Is this correct? (y/n): " yn
          if [[ $yn =~ $regex_YES ]]; then
            echo -e -n "\nUncommenting line ${BLUE_LIGHT}$user_locale_line_number${NORMAL} that contains locale ${BLUE_LIGHT}$user_locale${NORMAL}...\n"
            sed -i "$user_locale_line_number s/^#//" /etc/default/libc-locales
            echo -e -n "\nWriting locale ${BLUE_LIGHT}$user_locale${NORMAL} to /etc/locale.conf...\n\n"
            sed -i "/LANG=/s/.*/LANG=$user_locale/" /etc/locale.conf
            press_any_key_to_continue
            clear
            break 2
          elif [[ $yn =~ $regex_NO ]]; then
            echo -e -n "\n${RED_LIGHT}Please select another locale.${NORMAL}\n\n"
            press_any_key_to_continue
            break
          else
            echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
            press_any_key_to_continue
          fi
        done
      fi
    done
  fi

}

function header_ib {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}    ${GREEN_LIGHT}Bootloader installation${NORMAL}    ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function install_bootloader {

  while true; do

    if [[ "$luks_ot" == "2" ]]; then
      header_ib
      echo -e -n "\nLUKS version $luks_ot was previously selected.\n${BLUE_LIGHT}EFISTUB${NORMAL} will be used as bootloader.\n\n"
      bootloader="EFISTUB"
      press_any_key_to_continue
      echo
    else
      header_ib
      echo -e -n "\nSelect which ${BLUE_LIGHT}bootloader${NORMAL} do you want to use (EFISTUB, GRUB2): "
      read -r bootloader
    fi

    if [[ $bootloader =~ $regex_EFISTUB ]]; then
      echo -e -n "\nBootloader selected: ${BLUE_LIGHT}$bootloader${NORMAL}.\n"
      echo -e -n "\nMounting $boot_partition to /boot...\n"
      mkdir /TEMPBOOT
      cp -pr /boot/* /TEMPBOOT/
      rm -rf /boot/*
      mount -o rw,noatime "$boot_partition" /boot
      cp -pr /TEMPBOOT/* /boot/
      rm -rf /TEMPBOOT
      echo -e -n "\nSetting correct options in /etc/default/efibootmgr-kernel-hook...\n"
      sed -i "/MODIFY_EFI_ENTRIES=0/s/0/1/" /etc/default/efibootmgr-kernel-hook
      if [[ $encryption_yn =~ $regex_YES ]]; then
        sed -i "/# OPTIONS=/s/.*/OPTIONS=\"loglevel=4 rd.auto=1 rd.luks.name=$LUKS_UUID=$encrypted_name\"/" /etc/default/efibootmgr-kernel-hook
        if [[ "$hdd_ssd" == "ssd" ]]; then
          sed -i "/OPTIONS=/s/\"$/ rd.luks.allow-discards=$LUKS_UUID&/" /etc/default/efibootmgr-kernel-hook
        fi
      elif { [[ $encryption_yn =~ $regex_NO ]]; } && { [[ $lvm_yn =~ $regex_YES ]]; }; then
        sed -i "/# OPTIONS=/s/.*/OPTIONS=\"loglevel=4 rd.auto=1\"/" /etc/default/efibootmgr-kernel-hook
      else
        sed -i "/# OPTIONS=/s/.*/OPTIONS=\"loglevel=4\"/" /etc/default/efibootmgr-kernel-hook
      fi
      sed -i "/# DISK=/s|.*|DISK=\"\$(lsblk -pd -no pkname \$(findmnt -enr -o SOURCE -M /boot))\"|" /etc/default/efibootmgr-kernel-hook
      sed -i "/# PART=/s_.*_PART=\"\$(lsblk -pd -no pkname \$(findmnt -enr -o SOURCE -M /boot) | grep --color=never -Eo \\\\\"[0-9]+\$\\\\\")\"_" /etc/default/efibootmgr-kernel-hook
      echo -e -n "\nModifying /etc/kernel.d/post-install/50-efibootmgr to keep EFI entry after reboot...\n"
      sed -i "/efibootmgr -qo \$bootorder/s/^/#/" /etc/kernel.d/post-install/50-efibootmgr
      echo -e -n "\n${RED_LIGHT}Keep in mind that to keep the new EFI entry after each reboot,${NORMAL}\n"
      echo -e -n "${RED_LIGHT}the last line of /etc/kernel.d/post-install/50-efibootmgr has been commented.${NORMAL}\n"
      echo -e -n "${RED_LIGHT}Probably you will have to comment the same line after each efibootmgr update.${NORMAL}\n\n"
      break

    elif [[ $bootloader =~ $regex_GRUB2 ]]; then
      echo -e -n "\nBootloader selected: ${BLUE_LIGHT}$bootloader${NORMAL}.\n"

      # Fix kdfontop.c error
      # https://github.com/torvalds/linux/blob/master/Documentation/fb/fbcon.rst
      sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ fbcon=nodefer&/" /etc/default/grub

      if [[ $encryption_yn =~ $regex_YES ]]; then
        echo -e -n "\nEnabling CRYPTODISK in GRUB...\n"
        echo -e -n "\nGRUB_ENABLE_CRYPTODISK=y\n" >>/etc/default/grub
        sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ rd.auto=1 rd.luks.name=$LUKS_UUID=$encrypted_name&/" /etc/default/grub
        if [[ "$hdd_ssd" == "ssd" ]]; then
          sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ rd.luks.allow-discards=$LUKS_UUID&/" /etc/default/grub
        fi
      elif { [[ $encryption_yn =~ $regex_NO ]]; } && { [[ $lvm_yn =~ $regex_YES ]]; }; then
        sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ rd.auto=1&/" /etc/default/grub
      fi

      if ! grep -q efivar /proc/mounts; then
        echo -e -n "\nMounting efivarfs...\n"
        mount -t efivarfs efivarfs /sys/firmware/efi/efivars/
      fi

      while true; do
        echo -e -n "\nSelect a ${BLUE_LIGHT}bootloader-id${NORMAL} that will be used for grub install: "
        read -r bootloader_id
        if [[ -z "$bootloader_id" ]]; then
          echo -e -n "\n${RED_LIGHT}Please enter a valid bootloader-id.${NORMAL}\n\n"
          press_any_key_to_continue
        else
          while true; do
            echo -e -n "\nYou entered: ${BLUE_LIGHT}$bootloader_id${NORMAL}.\n\n"
            read -r -p "Is this the desired bootloader-id? (y/n): " yn
            if [[ $yn =~ $regex_YES ]]; then
              if [[ $encryption_yn =~ $regex_YES ]]; then
                echo -e -n "\nGenerating random key to avoid typing password twice at boot...\n\n"
                dd bs=512 count=4 if=/dev/random of=/boot/volume.key
                echo -e -n "\nRandom key generated, unlocking the encrypted partition...\n\n"
                if ! cryptsetup luksAddKey "$root_partition" /boot/volume.key; then
                  echo -e -n "\n${RED_LIGHT}Something went wrong, killing script...${NORMAL}\n\n"
                  kill_script
                else
                  chmod 000 /boot/volume.key
                  chmod -R g-rwx,o-rwx /boot
                  echo -e -n "\nAdding random key to /etc/crypttab...\n"
                  echo -e "\n$encrypted_name UUID=$LUKS_UUID /boot/volume.key luks\n" >>/etc/crypttab
                  echo -e -n "\nAdding random key to dracut configuration files...\n"
                  echo -e "install_items+=\" /boot/volume.key /etc/crypttab \"" >>/etc/dracut.conf.d/10-crypt.conf
                  echo -e -n "\nGenerating new dracut initramfs...\n\n"
                  press_any_key_to_continue
                  echo
                  dracut --regenerate-all --force --hostonly
                fi
              fi
              echo -e -n "\nInstalling GRUB on ${BLUE_LIGHT}/boot/efi${NORMAL} partition with ${BLUE_LIGHT}$bootloader_id${NORMAL} as bootloader-id...\n\n"
              mkdir -p /boot/efi
              mount -o rw,noatime "$boot_partition" /boot/efi/
              grub-install --target=x86_64-efi --boot-directory=/boot --efi-directory=/boot/efi --bootloader-id="$bootloader_id" --recheck
              echo -e -n "\nEnabling grub snapshot service at first boot...\n"
              ln -s /etc/sv/grub-btrfs /etc/runit/runsvdir/default/
              break 3
            elif [[ $yn =~ $regex_NO ]]; then
              echo -e -n "\n${RED_LIGHT}Please select another bootloader-id.${NORMAL}\n\n"
              press_any_key_to_continue
              break
            else
              echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
              press_any_key_to_continue
            fi
          done
        fi
      done

    else
      echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
    fi

  done

  if [[ $lvm_yn =~ $regex_YES ]] && [[ "$hdd_ssd" == "ssd" ]]; then
    echo -e -n "\nEnabling SSD trim for LVM...\n"
    sed -i 's/issue_discards = 0/issue_discards = 1/' /etc/lvm/lvm.conf
  fi

  export UEFI_UUID=$(blkid -s UUID -o value "$boot_partition")
  echo -e -n "\nWriting EFI partition to /etc/fstab...\n"
  if [[ $bootloader =~ $regex_EFISTUB ]]; then
    echo -e "\n# EFI partition\nUUID=$UEFI_UUID /boot vfat defaults,noatime 0 2" >>/etc/fstab
  elif [[ $bootloader =~ $regex_GRUB2 ]]; then
    echo -e "\n# EFI partition\nUUID=$UEFI_UUID /boot/efi vfat defaults,noatime 0 2" >>/etc/fstab
  fi

  echo -e -n "\nBootloader ${BLUE_LIGHT}$bootloader${NORMAL} successfully installed.\n\n"
  press_any_key_to_continue
  clear
  header_ib

  if [[ $bootloader =~ $regex_GRUB2 ]]; then
    while true; do
      echo -e -n "\nDo you want to set ${BLUE_LIGHT}${user_keyboard_layout}${NORMAL} keyboard layout also for GRUB2? (y/n): "
      read -r yn
      if [[ $yn =~ $regex_YES ]]; then
        if [[ $lvm_yn =~ $regex_YES ]]; then
          if [[ $encryption_yn =~ $regex_YES ]]; then
            root_line=$(echo -e -n "cryptomount -u ${LUKS_UUID//-/}\nset root=(lvm/"$vg_name"-"$lv_root_name")\n")
          else
            root_line="set root=(lvm/$vg_name-$lv_root_name)"
          fi
        else
          if [[ $encryption_yn =~ $regex_YES ]]; then
            root_line=$(echo -e -n "cryptomount -u ${LUKS_UUID//-/}\nset root=(cryptouuid/${LUKS_UUID//-/})\n")
          else
            disk=$(blkid -s UUID -o value $final_drive)
            root_line=$(echo -e -n "search --no-floppy --fs-uuid $disk --set pre_root\nset root=(\\\$pre_root)\n")
          fi
        fi

        echo -e -n "\nCreating /etc/kernel.d/post-install/51-grub_ckb...\n"

        cat <<End >>/etc/kernel.d/post-install/51-grub_ckb
#! /bin/sh
#
# Create grubx64.efi containing custom keyboard layout
# Requires: ckbcomp, grub2, xkeyboard-config
#

if [ ! -f /boot/efi/EFI/$bootloader_id/ORIG_grubx64.efi_ORIG ] ; then
    if [ ! -f /boot/efi/EFI/$bootloader_id/grubx64.efi ] ; then
        echo -e -n "\nFIle /boot/efi/EFI/$bootloader_id/grubx64.efi not found, install GRUB2 first!\n"
        exit 1
    else
        mv /boot/efi/EFI/$bootloader_id/grubx64.efi /boot/efi/EFI/$bootloader_id/ORIG_grubx64.efi_ORIG
    fi
fi

for file in $user_keyboard_layout.gkb early-grub.cfg grubx64_ckb.efi memdisk_ckb.tar ; do
    if [ -f /boot/grub/\$file ] ; then
        rm -f /boot/grub/\$file
    fi
done

grub-kbdcomp --output=/boot/grub/$user_keyboard_layout.gkb $user_keyboard_layout 2> /dev/null

tar --create --file=/boot/grub/memdisk_ckb.tar --directory=/boot/grub/ $user_keyboard_layout.gkb 2> /dev/null

cat << EndOfGrubConf >> /boot/grub/early-grub.cfg
set gfxpayload=keep
loadfont=unicode
terminal_output gfxterm
terminal_input at_keyboard
keymap (memdisk)/$user_keyboard_layout.gkb

${root_line}/@
set prefix=\\\$root/boot/grub

configfile \\\$prefix/grub.cfg
EndOfGrubConf

grub-mkimage --config=/boot/grub/early-grub.cfg --output=/boot/grub/grubx64_ckb.efi --format=x86_64-efi --memdisk=/boot/grub/memdisk_ckb.tar diskfilter gcry_rijndael gcry_sha256 ext2 memdisk tar at_keyboard keylayouts configfile gzio part_gpt all_video efi_gop efi_uga video_bochs video_cirrus echo linux font gfxterm gettext gfxmenu help reboot terminal test search search_fs_file search_fs_uuid search_label cryptodisk luks lvm btrfs

if [ -f /boot/efi/EFI/$bootloader_id/grubx64.efi ] ; then
    rm -f /boot/efi/EFI/$bootloader_id/grubx64.efi
fi

cp /boot/grub/grubx64_ckb.efi /boot/efi/EFI/$bootloader_id/grubx64.efi
End

        chmod +x /etc/kernel.d/post-install/51-grub_ckb
        echo -e -n "\nReconfiguring kernel...\n\n"
        kernelver_pre=$(ls /lib/modules/)
        kernelver="${kernelver_pre%.*}"
        xbps-reconfigure -f linux"$kernelver"
        break

      elif [[ $yn =~ $regex_NO ]]; then
        clear
        break
      else
        echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
        press_any_key_to_continue
        clear
      fi
    done
  fi

  echo -e -n "\nConfiguring AppArmor and setting it to enforce...\n"
  sed -i "/APPARMOR=/s/.*/APPARMOR=enforce/" /etc/default/apparmor
  sed -i "/#write-cache/s/^#//" /etc/apparmor/parser.conf
  sed -i "/#show_notifications/s/^#//" /etc/apparmor/notify.conf
  if [[ $bootloader =~ $regex_EFISTUB ]]; then
    sed -i "/OPTIONS=/s/\"$/ apparmor=1 security=apparmor&/" /etc/default/efibootmgr-kernel-hook
    echo -e -n "\nReconfiguring kernel...\n\n"
    kernelver_pre=$(ls /lib/modules/)
    kernelver=$(echo ${kernelver_pre%.*})
    xbps-reconfigure -f linux"$kernelver"
  elif [[ $bootloader =~ $regex_GRUB2 ]]; then
    sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ apparmor=1 security=apparmor&/" /etc/default/grub
    echo -e -n "\nUpdating grub...\n\n"
    update-grub
  fi

  echo
  press_any_key_to_continue
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

  while true; do

    header_cs
    echo -e -n "\nDo you want to create a ${BLUE_LIGHT}swapfile${NORMAL} in ${BLUE_LIGHT}/var/swap/${NORMAL} btrfs subvolume?\nThis will also enable ${BLUE_LIGHT}zswap${NORMAL}, a cache in RAM for swap.\nA swapfile is needed if you plan to use hibernation (y/n): "
    read -r yn

    if [[ $yn =~ $regex_YES ]]; then

      ram_size=$(free -g --si | awk -F " " 'FNR == 2 {print $2}')

      while true; do
        clear
        header_cs
        echo -e -n "\nYour system has ${BLUE_LIGHT}${ram_size}GB${NORMAL} of RAM.\n"
        echo -e -n "\nPress [ENTER] to create a swapfile of the same dimensions or choose the desired size in GB (numbers only): "
        read -r swap_size

        if [[ -z "$swap_size" ]] || [[ "$swap_size" -gt "0" ]]; then
          if [[ -z "$swap_size" ]]; then
            swap_size=$ram_size
          fi
          echo -e -n "\nA swapfile of ${BLUE_LIGHT}${swap_size}GB${NORMAL} will be created in ${BLUE_LIGHT}/var/swap/${NORMAL} btrfs subvolume...\n\n"
          btrfs subvolume create /var/swap
          truncate -s 0 /var/swap/swapfile
          chattr +C /var/swap/swapfile
          chmod 600 /var/swap/swapfile
          dd if=/dev/zero of=/var/swap/swapfile bs=100M count="$((${swap_size} * 10))" status=progress
          mkswap --label SwapFile /var/swap/swapfile
          swapon /var/swap/swapfile
          gcc -O2 "$HOME"/btrfs_map_physical.c -o "$HOME"/btrfs_map_physical
          RESUME_OFFSET=$(($("$HOME"/btrfs_map_physical /var/swap/swapfile | awk -F " " 'FNR == 2 {print $NF}') / $(getconf PAGESIZE)))
          if [[ $bootloader =~ $regex_EFISTUB ]]; then
            sed -i "/OPTIONS=/s/\"$/ resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET&/" /etc/default/efibootmgr-kernel-hook
          elif [[ $bootloader =~ $regex_GRUB2 ]]; then
            sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET&/" /etc/default/grub
          fi
          echo -e "\n# SwapFile\n/var/swap/swapfile none swap defaults 0 0" >>/etc/fstab
          echo -e -n "\nEnabling zswap...\n"
          echo "add_drivers+=\" lz4hc lz4hc_compress z3fold \"" >>/etc/dracut.conf.d/40-add_zswap_drivers.conf
          echo -e -n "\nRegenerating dracut initramfs...\n\n"
          press_any_key_to_continue
          echo
          dracut --regenerate-all --force --hostonly
          if [[ $bootloader =~ $regex_EFISTUB ]]; then
            sed -i "/OPTIONS=/s/\"$/ zswap.enabled=1 zswap.max_pool_percent=25 zswap.compressor=lz4hc zswap.zpool=z3fold&/" /etc/default/efibootmgr-kernel-hook
            echo -e -n "\nReconfiguring kernel...\n\n"
            kernelver_pre=$(ls /lib/modules/)
            kernelver=$(echo ${kernelver_pre%.*})
            xbps-reconfigure -f linux"$kernelver"
          elif [[ $bootloader =~ $regex_GRUB2 ]]; then
            sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ zswap.enabled=1 zswap.max_pool_percent=25 zswap.compressor=lz4hc zswap.zpool=z3fold&/" /etc/default/grub
            echo -e -n "\nUpdating grub...\n\n"
            update-grub
          fi
          swapoff --all
          echo -e -n "\n${GREEN_LIGHT}Swapfile successfully created and zswap successfully enabled.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
          break 2

        else
          echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
          press_any_key_to_continue
        fi

      done

    elif [[ $yn =~ $regex_NO ]]; then
      echo -e -n "\n${RED_LIGHT}Swapfile will not be created.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
      break

    else
      echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
    fi

  done

}

function header_cu {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}        ${GREEN_LIGHT}Create new users${NORMAL}       ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function create_user {

  while true; do

    header_cu
    echo -e -n "\nDo you want to ${BLUE_LIGHT}add${NORMAL} any ${BLUE_LIGHT}new user${NORMAL}?"
    echo -e -n "\nOnly non-root users can later configure Void Packages (y/n): "
    read -r yn
    if [[ $yn =~ $regex_YES ]]; then
      while true; do
        clear
        header_cu
        echo -e -n "\nPlease select a ${BLUE_LIGHT}name${NORMAL} for your new user (i.e. MyNewUser): "
        read -r newuser
        if [[ -z "$newuser" ]] || [[ $newuser =~ $regex_ROOT ]]; then
          echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
          press_any_key_to_continue
        elif getent passwd "$newuser" &>/dev/null; then
          echo -e -n "\n${RED_LIGHT}User ${newuser} already exists.\nPlease select another username.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
          break
        else
          while true; do
            echo -e -n "\nIs username ${BLUE_LIGHT}$newuser${NORMAL} okay? (y/n): "
            read -r yn
            if [[ $yn =~ $regex_NO ]]; then
              echo -e -n "\n${RED_LIGHT}Aborting, please select another name.${NORMAL}\n\n"
              press_any_key_to_continue
              clear
              break 2
            elif [[ $yn =~ $regex_YES ]]; then
              echo -e -n "\nAdding new user ${BLUE_LIGHT}$newuser${NORMAL} and giving access to groups:\n"
              echo -e -n "kmem, wheel, tty, tape, daemon, floppy, disk, lp, dialout, audio, video,"
              echo -e -n "\nutmp, cdrom, optical, mail, storage, scanner, kvm, input, plugdev, users.\n"
              useradd --create-home --groups kmem,wheel,tty,tape,daemon,floppy,disk,lp,dialout,audio,video,utmp,cdrom,optical,mail,storage,scanner,kvm,input,plugdev,users "$newuser"
              echo -e -n "\n${GREEN_LIGHT}User ${newuser} successfully created.${NORMAL}\n\n"
              press_any_key_to_continue
              newuser_yn="y"
              break 3
            else
              echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
              press_any_key_to_continue
            fi
          done
        fi
      done

    elif [[ $yn =~ $regex_NO ]]; then
      if [[ -z "$newuser_yn" ]]; then
        newuser_yn="n"
      fi
      clear
      break

    else
      echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
    fi

  done

}

function header_cup {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}     ${GREEN_LIGHT}Change users password${NORMAL}     ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function change_user_password {

  while true; do
    header_cup
    echo -e -n "\nDo you want to change users ${BLUE_LIGHT}password${NORMAL}? (y/n): "
    read -r yn
    if [[ $yn =~ $regex_YES ]]; then
      clear
      while true; do
        header_cup
        echo -e -n "\nListing all users:\n"
        awk -F':' '{print $1}' /etc/passwd
        echo -e -n "\nPlease select a valid user: "
        read -r user_change_password
        if grep -qw "$user_change_password" /etc/passwd; then
          while true; do
            echo
            if passwd "$user_change_password"; then
              echo -e -n "\n${GREEN_LIGHT}Password successfully changed for user ${user_change_password}.${NORMAL}\n\n"
              press_any_key_to_continue
              break 3
            else
              echo -e -n "\n${RED_LIGHT}Something went wrong, please try again.${NORMAL}\n\n"
              press_any_key_to_continue
              clear
              break 2
            fi
          done
        else
          echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
        fi
      done
    elif [[ $yn =~ $regex_NO ]]; then
      clear
      break
    else
      echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
    fi
  done
}

function header_cus {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}       ${GREEN_LIGHT}Change user shell${NORMAL}       ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function change_user_shell {

  while true; do
    header_cup
    echo -e -n "\nDo you want to change users default ${BLUE_LIGHT}shell${NORMAL}? (y/n): "
    read -r yn
    if [[ $yn =~ $regex_YES ]]; then
      clear
      while true; do
        header_cup
        echo -e -n "\nListing all users found in /etc/passwd:\n"
        awk -F':' '{print $1}' /etc/passwd
        echo -e -n "\nPlease select a valid user: "
        read -r user_change_shell
        if grep -q "$user_change_shell" /etc/passwd; then
          clear
          header_cus
          echo -e -n "\nListing all the available shells:\n\n"
          chsh --list-shells
          echo -e -n "\nWhich ${BLUE_LIGHT}shell${NORMAL} do you want to set for user ${BLUE_LIGHT}$user_change_shell${NORMAL}?"
          echo -e -n "\nPlease enter the full shell path (i.e. /bin/sh): "
          read -r set_user_shell
          if [[ ! -x "$set_user_shell" ]]; then
            echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
            press_any_key_to_continue
            clear
          else
            echo
            if chsh --shell "$set_user_shell" "$user_change_shell"; then
              echo -e -n "\n${GREEN_LIGHT}Default shell successfully changed.${NORMAL}\n\n"
              press_any_key_to_continue
            else
              echo -e -n "\n${RED_LIGHT}Something went wrong, please try again.${NORMAL}\n\n"
              press_any_key_to_continue
            fi
            clear
            break 3
          fi
        else
          echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
          break 2
        fi
      done
    elif [[ $yn =~ $regex_NO ]]; then
      clear
      break
    else
      echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
    fi
  done
}

function header_up {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}       ${GREEN_LIGHT}Uninstall package${NORMAL}       ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function uninstall_packages {

  while true; do
    header_up
    echo -e -n "\nDo you want to ${BLUE_LIGHT}uninstall${NORMAL} any package? (y/n): "
    read -r yn
    if [[ $yn =~ $regex_YES ]]; then
      clear
      while true; do
        header_up
        echo -e -n "\nListing all installed packages."
        echo -e -n "\nPress any key to continue and then press \"q\" to exit the list.\n\n"
        press_any_key_to_continue
        xpkg -m | less --RAW-CONTROL-CHARS --no-init
        echo -e -n "\nPlease enter all the packages you want to uninstall separated by spaces: "
        read -r user_uninstall_packages
        if xbps-remove $user_uninstall_packages; then
          echo -e -n "\n${GREEN_LIGHT}Packages were successfully uninstalled.${NORMAL}\n\n"
          press_any_key_to_continue
        else
          echo -e -n "\n${RED_LIGHT}Something went wrong, please try again.${NORMAL}\n\n"
          press_any_key_to_continue
        fi
        clear
        break 2
      done
    elif [[ $yn =~ $regex_NO ]]; then
      clear
      break
    else
      echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
    fi
  done

}

function header_eds {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}    ${GREEN_LIGHT}Enable/disable services${NORMAL}    ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function enable_disable_services {

  while true; do
    clear
    header_eds
    echo -e -n "\nDo you want to enable or disable any service?\n\n"
    select user_arch in Enable Disable back; do
      case "$user_arch" in
      Enable)
        clear
        header_eds
        echo -e -n "\nListing all the services that could be enabled...\n"
        ls --almost-all --color=always /etc/sv/
        echo -e -n "\nListing all the services that are already enabled...\n"
        ls --almost-all --color=always /etc/runit/runsvdir/default/
        echo -e -n "\nWhich service do you want to enable? (i.e. NetworkManager || back): "
        read -r service_enabler
        if [[ $service_enabler =~ $regex_BACK ]]; then
          clear
          break
        elif [[ ! -d /etc/sv/"$service_enabler" ]]; then
          echo -e -n "\n${RED_LIGHT}Service $service_enabler does not exist.${NORMAL}\n\n"
          press_any_key_to_continue
          break
        elif [[ -L /etc/runit/runsvdir/default/"$service_enabler" ]]; then
          echo -e -n "\n${RED_LIGHT}Service $service_enabler already enabled.${NORMAL}.\n\n"
          press_any_key_to_continue
          break
        elif [[ -z "$service_enabler" ]]; then
          echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
          press_any_key_to_continue
        else
          echo -e -n "\nEnabling service ${BLUE_LIGHT}$service_enabler${NORMAL}...\n"
          if ln -s /etc/sv/"$service_enabler" /etc/runit/runsvdir/default/; then
            echo -e -n "\n${GREEN_LIGHT}Service successfully enabled.${NORMAL}\n\n"
            press_any_key_to_continue
            clear
            break 2
          else
            echo -e -n "\n${RED_LIGHT}Something went wrong, please try again.${NORMAL}\n\n"
            press_any_key_to_continue
          fi
        fi
        ;;
      Disable)
        clear
        header_eds
        echo -e -n "\nListing all the services that could be disabled...\n"
        ls --almost-all --color=always /etc/runit/runsvdir/default/
        echo -e -n "\nWhich service do you want to disable? (i.e. NetworkManager || back): "
        read -r service_disabler
        if [[ $service_disabler =~ $regex_BACK ]]; then
          clear
          break
        elif [[ ! -L /etc/runit/runsvdir/default/"$service_disabler" ]]; then
          echo -e -n "\n${RED_LIGHT}Service $service_disabler does not exist.${NORMAL}\n\n"
          press_any_key_to_continue
          break
        elif [[ -z "$service_disabler" ]]; then
          echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
          press_any_key_to_continue
        else
          echo -e -n "\nDisabling service ${BLUE_LIGHT}$service_disabler${NORMAL}...\n"
          if rm -f /etc/runit/runsvdir/default/"$service_disabler"; then
            echo -e -n "\n${GREEN_LIGHT}Service successfully enabled.${NORMAL}\n\n"
            press_any_key_to_continue
            clear
            break 2
          else
            echo -e -n "\n${RED_LIGHT}Something went wrong, please try again.${NORMAL}\n\n"
            press_any_key_to_continue
            break
          fi
        fi
        ;;
      back)
        clear
        break 2
        ;;
      *)
        echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
        press_any_key_to_continue
        clear
        break
        ;;
      esac
    done
  done

}

function header_vp {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}    ${GREEN_LIGHT}Configure Void Packages${NORMAL}    ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function void_packages {

  if ping -c 1 8.8.8.8 &>/dev/null; then

    if [[ "$newuser_yn" == "y" ]]; then

      while true; do
        header_vp
        echo -e -n "\nDo you want to clone a ${BLUE_LIGHT}Void Packages${NORMAL} repository to a specific folder for a specific non-root user? (y/n): "
        read -r yn

        if [[ $yn =~ $regex_YES ]]; then
          while true; do
            clear
            header_vp
            echo -e -n "\nPlease enter an existing ${BLUE_LIGHT}username${NORMAL} (back): "
            read -r void_packages_username
            if [[ $void_packages_username =~ $regex_BACK ]]; then
              clear
              break
            elif [[ $void_packages_username =~ $regex_ROOT ]]; then
              echo -e -n "\n${RED_LIGHT}Root user cannot be used to configure Void Packages.${NORMAL}\n\n"
              press_any_key_to_continue
            elif ! getent passwd "$void_packages_username" &>/dev/null; then
              echo -e -n "\n${RED_LIGHT}User $void_packages_username do not exists.${RED_LIGHT}\n\n"
              press_any_key_to_continue
            else
              while true; do
                clear
                header_vp
                echo -e -n "\nUser selected: ${BLUE_LIGHT}$void_packages_username${NORMAL}\n"
                echo -e -n "\nPlease enter a ${BLUE_LIGHT}full empty path${NORMAL} where you want to clone Void Packages."
                echo -e -n "\nThe script will create that folder and then clone Void Packages into it (i.e. /home/user/MyVoidPackages/ || back): "
                read -r void_packages_path
                if [[ $void_packages_path =~ $regex_BACK ]]; then
                  clear
                  break
                elif [[ -z "$void_packages_path" ]]; then
                  echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
                  press_any_key_to_continue
                  clear
                else
                  while true; do
                    if [[ ! -d "$void_packages_path" ]]; then
                      if ! su - "$void_packages_username" --command "mkdir -p $void_packages_path 2> /dev/null"; then
                        echo -e -n "\n${RED_LIGHT}User $void_packages_username cannot create a folder in this directory.${NORMAL}"
                        echo -e -n "\n${RED_LIGHT}Please select another path.${NORMAL}\n\n"
                        press_any_key_to_continue
                        break
                      fi
                    else
                      if [[ -n $(ls -A "$void_packages_path") ]]; then
                        echo -e -n "\n${RED_LIGHT}Directory $void_packages_path${NORMAL} is not empty.\nPlease select another path.${NORMAL}\n\n"
                        press_any_key_to_continue
                        break
                      fi
                      if [[ $(stat --dereference --format="%U" "$void_packages_path") != "$void_packages_username" ]]; then
                        echo -e -n "\n${RED_LIGHT}User $void_packages_username doesn't have write permission in this directory.${NORMAL}\n"
                        echo -e- n "\n${RED_LIGHT}Please select another path.${NORMAL}\n\n"
                        press_any_key_to_continue
                        break
                      fi
                    fi
                    echo -e -n "\nPath selected: ${BLUE_LIGHT}$void_packages_path${NORMAL}\n"
                    echo -e -n "\nIs this correct? (y/n): "
                    read -r yn
                    if [[ $yn =~ $regex_NO ]]; then
                      echo -e -n "\n${RED_LIGHT}Aborting, select another path.${NORMAL}\n\n"
                      if [[ -z "$(ls -A $void_packages_path)" ]]; then
                        rm -rf "$void_packages_path"
                      fi
                      press_any_key_to_continue
                      clear
                      break
                    elif [[ $yn =~ $regex_YES ]]; then
                      while true; do
                        echo -e -n "\nDo you want to specify a ${BLUE_LIGHT}custom public repository${NORMAL}?"
                        echo -e -n "\nIf not, official repository will be used (y/n/back): "
                        read -r yn
                        if [[ $yn =~ $regex_NO ]]; then
                          echo -e -n "\n${GREEN_LIGHT}Official repository will be used.${NORMAL}\n"
                          git_cmd="git clone $void_packages_repo"
                          break
                        elif [[ $yn =~ $regex_YES ]]; then
                          while true; do
                            echo -e -n "\n\nPlease enter a public repository url and optionally a branch (i.e. https://github.com/MyPersonal/VoidPackages MyBranch): "
                            read -r void_packages_custom_repo void_packages_custom_branch
                            if [[ -z "$void_packages_custom_branch" ]]; then
                              repo_check=$(GIT_TERMINAL_PROMPT=0 git ls-remote "$void_packages_custom_repo" | wc -l)
                            else
                              repo_check=$(GIT_TERMINAL_PROMPT=0 git ls-remote "$void_packages_custom_repo" "$void_packages_custom_branch" | wc -l)
                            fi
                            if [[ "$repo_check" != "0" ]]; then
                              echo -e -n "\nCustom repository ${BLUE_LIGHT}$void_packages_custom_repo${NORMAL} will be used.\n"
                              if [[ -z "$void_packages_custom_branch" ]]; then
                                git_cmd="git clone $void_packages_custom_repo"
                              else
                                git_cmd="git clone $void_packages_custom_repo -b $void_packages_custom_branch"
                              fi
                              break 2
                            else
                              echo -e -n "\n\n${RED_LIGHT}Please enter a valid public repository url.${NORMAL}\n\n"
                              press_any_key_to_continue
                              break
                            fi
                          done
                        elif [[ $yn =~ $regex_BACK ]]; then
                          clear
                          break 2
                        else
                          echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
                          press_any_key_to_continue
                        fi
                      done
                      echo -e -n "\nSwitching to user ${BLUE_LIGHT}$void_packages_username${NORMAL}...\n\n"
                      su --login --shell=/bin/bash --whitelist-environment=git_cmd,void_packages_path "$void_packages_username" <<EOSU
$git_cmd "$void_packages_path"
echo -e -n "\nEnabling restricted packages...\n"
echo "XBPS_ALLOW_RESTRICTED=yes" >> "$void_packages_path"/etc/conf
EOSU
                      echo -e -n "\nLogging out user ${BLUE_LIGHT}$void_packages_username${NORMAL}...\n"
                      echo -e -n "\n${GREEN_LIGHT}Void Packages successfully cloned and configured.${NORMAL}\n\n"
                      press_any_key_to_continue
                      clear
                      break 4
                    else
                      echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
                      press_any_key_to_continue
                    fi
                  done
                fi
              done
            fi
          done

        elif [[ $yn =~ $regex_NO ]]; then
          clear
          break

        else
          echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
        fi

      done

    elif [[ "$newuser_yn" == "n" ]]; then
      header_vp
      echo -e -n "\n${RED_LIGHT}Please add at least one non-root user to configure additional Void Packages.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
    fi

  else
    header_vp
    echo -e -n "\n${RED_LIGHT}No internet connection available.${NORMAL}\n\n"
    press_any_key_to_continue
    clear
  fi

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
  echo -e -n "\nReconfiguring every package...\n\n"
  press_any_key_to_continue
  echo
  xbps-reconfigure -fa

  echo -e -n "\n${GREEN_LIGHT}Everything's done, exiting chroot...${NORMAL}\n\n"
  press_any_key_to_continue
  clear

}

function chroot_shell {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}       ${GREEN_LIGHT}Chroot Bash Shell${NORMAL}       ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

  echo -e -n "\nType \"exit\" anytime to go back to chroot menu.\n\n"

  PS1="${GREEN_DARK}[${NORMAL} ${GREEN_LIGHT}chroot${NORMAL} ${GREEN_DARK}|${NORMAL} ${GREEN_LIGHT}\w${NORMAL} ${GREEN_DARK}]${NORMAL} # " /bin/bash

}

# Main

function header_chroot_main {
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}   ${GREEN_LIGHT}Void Linux Installer Menu${NORMAL}   ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
}

function chroot_main {

  while true; do

    header_chroot_main

    echo -e -n "\n1) Create users"
    echo -e -n "\n2) Change user password"
    echo -e -n "\n3) Change user default shell"

    echo

    echo -e -n "\n4) Change repository mirror"
    echo -e -n "\n5) Install additional packages"
    echo -e -n "\n6) Uninstall packages"
    echo -e -n "\n7) Configure Void Packages"

    echo

    echo -e -n "\n8) Enable/disable services"

    echo

    echo -e -n "\n9) Open /bin/bash shell"

    echo

    echo -e -n "\nq) ${RED_LIGHT}Finish last steps and quit chroot.${NORMAL}\n"

    echo -e -n "\nUser selection: "
    read -r menu_selection

    case "${menu_selection}" in
    1)
      clear
      create_user
      clear
      ;;
    2)
      clear
      change_user_password
      clear
      ;;
    3)
      clear
      change_user_shell
      clear
      ;;
    4)
      clear
      xmirror
      clear
      ;;
    5)
      clear
      xs
      clear
      ;;
    6)
      clear
      uninstall_packages
      clear
      ;;
    7)
      clear
      void_packages
      clear
      ;;
    8)
      clear
      enable_disable_services
      clear
      ;;
    9)
      clear
      chroot_shell
      clear
      ;;
    q)
      clear
      finish_chroot
      break
      ;;
    *)
      echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
      ;;
    esac
  done

}

initial_configuration
install_bootloader
create_swapfile
chroot_main
exit 0
