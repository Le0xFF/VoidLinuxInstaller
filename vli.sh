#! /bin/bash

# Author: Le0xFF
# Script name: vli.sh
# Github repo: https://github.com/Le0xFF/VoidLinuxInstaller
#
# Description: My first attempt at creating a bash script, trying to converting my gist into a bash script. Bugs are more than expected.
#              https://gist.github.com/Le0xFF/ff0e3670c06def675bb6920fe8dd64a3
#

# Catch kill signals

trap "kill_script" INT TERM QUIT

# Variables
## Can be manually modified
user_drive=''
boot_partition=''
root_partition=''
boot_label=''
root_label=''
current_xkeyboard_layout=''
user_keyboard_layout=''
## Better not change them
drive_partition_selection='0'
encryption_yn='n'
luks_ot=''
encrypted_name=''
encrypted_partition=''
lvm_yn='n'
vg_name=''
lv_root_name=''
lvm_partition=''
final_drive=''
hdd_ssd=''

# Constants

regex_GPT="[Gg][Pp][Tt]"
regex_YES="[Yy]"
regex_NO="[Nn]"
regex_BACK="[Bb][Aa][Cc][Kk]"
regex_EFISTUB="[Ee][Ff][Ii][Ss][Tt][Uu][Bb]"
regex_GRUB2="[Gg][Rr][Uu][Bb][2]"
regex_ROOT="[Rr][Oo][Oo][Tt]"
void_packages_repo="https://github.com/void-linux/void-packages.git"

# Colours

BLUE_LIGHT="\e[1;34m"
BLUE_LIGHT_FIND="\033[1;34m"
GREEN_DARK="\e[0;32m"
GREEN_LIGHT="\e[1;32m"
NORMAL="\e[0m"
NORMAL_FIND="\033[0m"
RED_LIGHT="\e[1;31m"
BLACK_FG_WHITE_BG="\e[30;47m"

# Functions

function press_any_key_to_continue {

  echo -e -n "${BLACK_FG_WHITE_BG}[Press any key to continue...]${NORMAL}"
  read -n 1 -r _key

}

function kill_script {

  echo -e -n "\n\n${RED_LIGHT}Kill or quit signal captured.\nUnmonting what should have been mounted, cleaning and closing everything...${NORMAL}\n\n"

  if findmnt /mnt &>/dev/null; then
    umount --recursive /mnt
  fi

  if [[ "$lvm_yn" == "y" ]] || [[ "$lvm_yn" == "Y" ]]; then
    lvchange -an /dev/mapper/"$vg_name"-"$lv_root_name"
    vgchange -an /dev/mapper/"$vg_name"
  fi

  if [[ "$encryption_yn" == "y" ]] || [[ "$encryption_yn" == "Y" ]]; then
    cryptsetup close /dev/mapper/"$encrypted_name"
  fi

  if [[ -f "$HOME"/chroot.sh ]]; then
    rm -f "$HOME"/chroot.sh
  fi

  echo -e -n "\n${GREEN_LIGHT}Everything's done, quitting.${NORMAL}\n\n"
  exit 1

}

function check_if_bash {

  if [[ "$(/bin/ps -p $$ | awk 'NR==2 {print $4}')" != "bash" ]]; then
    echo -e -n "Please run this script with bash shell: \"bash vli.sh\".\n"
    exit 1
  fi

}

function check_if_run_as_root {

  if [[ "$UID" != "0" ]]; then
    echo -e -n "Please run this script as root.\n"
    exit 1
  fi

}

function check_if_uefi {

  if ! grep efivar -q /proc/mounts; then
    if ! mount -t efivarfs efivarfs /sys/firmware/efi/efivars/ &>/dev/null; then
      echo -e -n "Please run this script only on a UEFI system."
      exit 1
    fi
  fi

}

function create_chroot_script {

  if [[ -f "$HOME"/chroot.sh ]]; then
    rm -f "$HOME"/chroot.sh
  fi

  cat >>"$HOME"/chroot.sh <<'EndOfChrootScript'
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
        sed -i "/# OPTIONS=/s/.*/OPTIONS=\"loglevel=4 fbcon=nodefer rd.auto=1 rd.luks.name=$LUKS_UUID=$encrypted_name\"/" /etc/default/efibootmgr-kernel-hook
        if [[ "$hdd_ssd" == "ssd" ]]; then
          sed -i "/OPTIONS=/s/\"$/ rd.luks.allow-discards=$LUKS_UUID&/" /etc/default/efibootmgr-kernel-hook
        fi
      elif { [[ $encryption_yn =~ $regex_NO ]]; } && { [[ $lvm_yn =~ $regex_YES ]]; }; then
        sed -i "/# OPTIONS=/s/.*/OPTIONS=\"loglevel=4 fbcon=nodefer rd.auto=1\"/" /etc/default/efibootmgr-kernel-hook
      else
        sed -i "/# OPTIONS=/s/.*/OPTIONS=\"loglevel=4 fbcon=nodefer\"/" /etc/default/efibootmgr-kernel-hook
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
          echo -e -n "\nA swapfile of ${BLUE_LIGHT}${swap_size}GB${NORMAL} will be created in ${BLUE_LIGHT}/swap/${NORMAL} btrfs subvolume...\n\n"
          btrfs filesystem mkswapfile /swap/swapfile --size "${swap_size}"G
          mkswap --label SwapFile /swap/swapfile
          swapon /swap/swapfile
          RESUME_UUID=$(findmnt -no UUID -T /swap/swapfile)
          RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r /swap/swapfile)
          if [[ $bootloader =~ $regex_EFISTUB ]]; then
            sed -i "/OPTIONS=/s/\"$/ resume=UUID=$RESUME_UUID resume_offset=$RESUME_OFFSET&/" /etc/default/efibootmgr-kernel-hook
          elif [[ $bootloader =~ $regex_GRUB2 ]]; then
            sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ resume=UUID=$RESUME_UUID resume_offset=$RESUME_OFFSET&/" /etc/default/grub
          fi
          echo -e -n "\n# Swap Subvolume\nUUID=$ROOT_UUID /swap btrfs $BTRFS_OPT,subvol=@swap 0 2\n" >>/etc/fstab
          echo -e -n "\n# SwapFile\n/swap/swapfile none swap sw 0 0\n" >>/etc/fstab
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

EndOfChrootScript

  if [[ ! -f "$HOME"/chroot.sh ]]; then
    echo -e -n "Please run this script again to be sure that $HOME/chroot.sh script is created too."
    exit 1
  fi

  chmod +x "$HOME"/chroot.sh

}

function intro {

  clear

  echo -e -n "     ${GREEN_LIGHT}pQQQQQQQQQQQQppq${NORMAL}           ${GREEN_DARK}###${NORMAL} ${GREEN_LIGHT}Void Linux installer script${NORMAL} ${GREEN_DARK}###${NORMAL}\n"
  echo -e -n "     ${GREEN_LIGHT}p               Q${NORMAL}   \n"
  echo -e -n "      ${GREEN_LIGHT}pppQppQppppQ    Q${NORMAL}         My first attempt at creating a bash script.\n"
  echo -e -n " ${GREEN_DARK}{{{{{${NORMAL}            ${GREEN_LIGHT}p    Q${NORMAL}        Bugs and unicorns farts are expected.\n"
  echo -e -n "${GREEN_DARK}{    {${NORMAL}   ${GREEN_LIGHT}dpppppp   p    Q${NORMAL}\n"
  echo -e -n "${GREEN_DARK}{   {${NORMAL}   ${GREEN_LIGHT}p       p   p   Q${NORMAL}       This script try to automate what my gist describes.\n"
  echo -e -n "${GREEN_DARK}{   {${NORMAL}   ${GREEN_LIGHT}p       Q   p   Q${NORMAL}       Link to the gist: ${BLUE_LIGHT}https://gist.github.com/Le0xFF/ff0e3670c06def675bb6920fe8dd64a3${NORMAL}\n"
  echo -e -n "${GREEN_DARK}{   {${NORMAL}   ${GREEN_LIGHT}p       Q   p   Q${NORMAL}\n"
  echo -e -n "${GREEN_DARK}{    {${NORMAL}   ${GREEN_LIGHT}ppppppQ   p    Q${NORMAL}       This script will install Void Linux with BTRFS as filesystem and optionally:\n"
  echo -e -n " ${GREEN_DARK}{    {${NORMAL}            ${GREEN_LIGHT}ppppQ${NORMAL}        LVM and Full Disk Encryption using LUKS1/2 and it will eventually enable trim on SSD.\n"
  echo -e -n "  ${GREEN_DARK}{    {{{{{{{{{{{{${NORMAL}             To understand better what the script does, please look at the README: ${BLUE_LIGHT}https://github.com/Le0xFF/VoidLinuxInstaller${NORMAL}\n"
  echo -e -n "   ${GREEN_DARK}{               {${NORMAL}     \n"
  echo -e -n "    ${GREEN_DARK}{{{{{{{{{{{{{{{{${NORMAL}            [Press any key to begin with the process...]\n"

  read -n 1 -r key

  clear

}

function header_skl {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}     ${GREEN_LIGHT}Keyboard layout change${NORMAL}    ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function set_keyboard_layout {

  while true; do

    while true; do
      if [[ -n "${current_xkeyboard_layout}" ]] || [[ -n "${user_keyboard_layout}" ]]; then
        header_skl
        echo -e -n "\nYour current keyboard layout is ${BLUE_LIGHT}${current_xkeyboard_layout:-${user_keyboard_layout}}${NORMAL}, do you want to change it? (y/n/back): "
        read -r yn
        if [[ $yn =~ ${regex_YES} ]]; then
          clear
          break
        elif [[ $yn =~ ${regex_NO} ]]; then
          user_keyboard_layout="${current_xkeyboard_layout:-${user_keyboard_layout}}"
          echo -e -n "\nKeyboard layout won't be changed.\n\n"
          press_any_key_to_continue
          clear
          break 2
        elif [[ $yn =~ ${regex_BACK} ]]; then
          clear
          break 2
        else
          echo -e -n "\nNot a valid input.\n\n"
          press_any_key_to_continue
          clear
        fi
      else
        break
      fi
    done

    header_skl
    echo -e -n "\nThe keyboard layout will be also set configured for your future installed system.\n"
    echo -e -n "\nPress any key to list all the keyboard layouts.\nMove with arrow keys and press \"q\" to exit the list.\n\n"
    press_any_key_to_continue
    echo

    find /usr/share/kbd/keymaps/ \
      -type f \
      -iname "*.map.gz" \
      -printf "${BLUE_LIGHT_FIND}%f\0${NORMAL_FIND}\n" |
      sed -e 's/\..*$//' |
      sort |
      less --RAW-CONTROL-CHARS --no-init

    while true; do
      echo -e -n "\nType the keyboard layout you want to set and press [ENTER]: "
      read -r user_keyboard_layout
      if loadkeys "$user_keyboard_layout" 2>/dev/null; then
        echo -e -n "\nKeyboad layout set to: ${BLUE_LIGHT}$user_keyboard_layout${NORMAL}.\n\n"
        press_any_key_to_continue
        clear
        break
      else
        echo -e "\n${RED_LIGHT}Not a valid keyboard layout.${NORMAL}"
      fi
    done

    break
  done

}

function header_cti {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}   ${GREEN_LIGHT}Setup internet connection${NORMAL}   ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function connect_to_internet {

  while true; do

    header_cti
    echo -e -n "\nDo you want to use wifi? (y/n/back): "
    read -r yn
    if [[ $yn =~ ${regex_YES} ]]; then
      if pgrep NetworkManager &>/dev/null; then
        echo
        ip --color=auto link show
        echo
        echo -e -n "Input you wifi interface name (i.e. wlp2s0): "
        read -r WIFI_INTERFACE
        echo -e -n "\nInput a preferred name to give to your internet connection: "
        read -r WIFI_NAME
        echo -e -n "Input your wifi SSID or BSSID: "
        read -r WIFI_SSID
        nmcli connection add type wifi con-name "${WIFI_NAME}" ifname "${WIFI_INTERFACE}" ssid "${WIFI_SSID}"
        nmcli connection modify "${WIFI_NAME}" wifi-sec.key-mgmt wpa-psk
        nmcli --ask connection up "${WIFI_NAME}"
        if ping -c 2 8.8.8.8 &>/dev/null; then
          echo -e -n "\n${GREEN_LIGHT}Successfully connected to the internet.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
          break
        else
          echo -e -n "\n${RED_LIGHT}No internet connection detected.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
        fi
      else
        echo -e -n "\n\n${RED_LIGHT}Please be sure that NetworkManager is running.${NORMAL}\n\n"
        press_any_key_to_continue
        clear
        break
      fi

    elif [[ $yn =~ ${regex_NO} ]]; then
      if ping -c 1 8.8.8.8 &>/dev/null; then
        echo -e -n "\n${GREEN_LIGHT}Successfully connected to the internet.${NORMAL}\n\n"
      else
        echo -e -n "\n${RED_LIGHT}Please check or connect your ethernet cable.${NORMAL}\n\n"
      fi
      press_any_key_to_continue
      clear
      break

    elif [[ $yn =~ ${regex_BACK} ]]; then
      clear
      break

    else
      echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
    fi

  done

}

function header_sd {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}       ${GREEN_LIGHT}Destination drive${NORMAL}       ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function select_destination {

  if [[ "${drive_partition_selection}" == "3" ]] ||
    { [[ "${drive_partition_selection}" == "6" ]] && [[ -b "$user_drive" ]]; } ||
    { [[ "${drive_partition_selection}" == "7" ]] && [[ -b "$user_drive" ]]; }; then
    while true; do
      header_sd
      if [[ "${drive_partition_selection}" == "3" ]]; then
        echo -e -n "\nPrinting all the connected drives:\n\n"
        lsblk -p
        echo -e -n "\nWhich ${BLUE_LIGHT}drive${NORMAL} do you want to select as ${BLUE_LIGHT}destination drive${NORMAL}?"
        echo -e -n "\nIt will be automatically selected as the drive to be formatted and partitioned."
        echo -e -n "\n\nPlease enter the full drive path (i.e. /dev/sda || back): "
        read -r user_drive
      elif [[ "${drive_partition_selection}" == "6" ]]; then
        echo -e -n "\nPrinting destination drive:\n\n"
        lsblk -p "${user_drive}"
        echo -e -n "\nWhich ${BLUE_LIGHT}partition${NORMAL} do you want to select as ${BLUE_LIGHT}EFI${NORMAL}?"
        echo -e -n "\n\nPlease enter the full partition path (i.e. /dev/sda1 || back): "
        read -r boot_partition
      elif [[ "${drive_partition_selection}" == "7" ]]; then
        echo -e -n "\nPrinting destination drive:\n\n"
        lsblk -p "${user_drive}"
        echo -e -n "\nWhich ${BLUE_LIGHT}partition${NORMAL} do you want to select as ${BLUE_LIGHT}ROOT${NORMAL}?"
        echo -e -n "\n\nPlease enter the full partition path (i.e. /dev/sda2 || back): "
        read -r root_partition
      fi

      if [[ $user_drive =~ ${regex_BACK} ]] || [[ $boot_partition =~ ${regex_BACK} ]] || [[ $root_partition =~ ${regex_BACK} ]]; then
        clear
        break
      elif { [[ "${drive_partition_selection}" == "3" ]] && [[ ! -b "$user_drive" ]]; } ||
        { [[ "${drive_partition_selection}" == "6" ]] && [[ ! -b "$boot_partition" ]]; } ||
        { [[ "${drive_partition_selection}" == "7" ]] && [[ ! -b "$root_partition" ]]; }; then
        echo -e -n "\n${RED_LIGHT}Please select a valid destination.${NORMAL}\n\n"
        press_any_key_to_continue
        clear
      else
        if [[ "${drive_partition_selection}" == "3" ]]; then
          echo -e -n "\nDrive selected as destination: ${BLUE_LIGHT}$user_drive${NORMAL}\n"
        elif [[ "${drive_partition_selection}" == "6" ]]; then
          echo -e -n "\nEFI partition selected as destination: ${BLUE_LIGHT}$boot_partition${NORMAL}\n"
        elif [[ "${drive_partition_selection}" == "7" ]]; then
          echo -e -n "\nROOT partition selected as destination: ${BLUE_LIGHT}$root_partition${NORMAL}\n"
        fi
        while true; do
          echo -e -n "\n${RED_LIGHT}DESTINATION WILL BE WIPED AND PARTITIONED, EVERY DATA INSIDE WILL BE LOST.${NORMAL}\n"
          echo -e -n "${RED_LIGHT}Are you sure you want to continue? (y/n):${NORMAL} "
          read -r yn

          if [[ $yn =~ ${regex_NO} ]]; then
            echo -e -n "\n${RED_LIGHT}Aborting, select another destination.${NORMAL}\n\n"
            press_any_key_to_continue
            clear
            break
          elif [[ $yn =~ ${regex_YES} ]]; then
            if [[ "${drive_partition_selection}" == "3" ]]; then
              if grep -q "$user_drive" /proc/mounts; then
                echo -e -n "\nDrive already mounted.\nChanging directory to $HOME and unmounting every partition...\n"
                cd "$HOME"
                umount --recursive "$(findmnt "$user_drive" | awk -F " " 'FNR == 2 {print $1}')"
                echo -e -n "\nDrive unmounted successfully.\n"
              fi
              echo -e -n "\n${GREEN_LIGHT}Correct drive selected.${NORMAL}\n\n"
              boot_partition=''
              root_partition=''
            elif [[ "${drive_partition_selection}" == "6" ]]; then
              if grep -q "$boot_partition" /proc/mounts; then
                echo -e -n "\nPartition already mounted.\nChanging directory to $HOME and unmounting partition...\n"
                cd "$HOME"
                umount --recursive "$(findmnt "$boot_partition" | awk -F " " 'FNR == 2 {print $1}')"
                echo -e -n "\nPartition unmounted successfully.\n"
              fi
              echo -e -n "\n${GREEN_LIGHT}Correct EFI partition selected.${NORMAL}\n\n"
            elif [[ "${drive_partition_selection}" == "7" ]]; then
              if grep -q "$root_partition" /proc/mounts; then
                echo -e -n "\nPartition already mounted.\nChanging directory to $HOME and unmounting partition...\n"
                cd "$HOME"
                umount --recursive "$(findmnt "$root_partition" | awk -F " " 'FNR == 2 {print $1}')"
                echo -e -n "\nPartition unmounted successfully.\n"
              fi
              echo -e -n "\n${GREEN_LIGHT}Correct ROOT partition selected.${NORMAL}\n\n"
            fi
            press_any_key_to_continue
            clear
            break 2
          else
            echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
            press_any_key_to_continue
            echo
          fi
        done
      fi

    done
  else
    header_dw
    echo -e -n "\n${RED_LIGHT}Please first select a valid destination drive.${NORMAL}\n\n"
    press_any_key_to_continue
    clear
  fi

}

function header_dw {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}          ${GREEN_LIGHT}Disk wiping${NORMAL}          ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function disk_wiping {

  if [[ ! -b "$user_drive" ]]; then
    header_dw
    echo -e -n "\n${RED_LIGHT}Please select a valid destination drive before wiping.${NORMAL}\n\n"
    press_any_key_to_continue
    clear
  else
    while true; do
      header_dw
      echo -e -n "\nDrive selected for wiping: ${BLUE_LIGHT}$user_drive${NORMAL}\n"
      echo -e -n "\n${RED_LIGHT}THIS DRIVE WILL BE WIPED, EVERY DATA INSIDE WILL BE LOST.${NORMAL}\n"
      echo -e -n "${RED_LIGHT}Are you sure you want to continue? (y/n):${NORMAL} "
      read -r yn

      if [[ $yn =~ ${regex_NO} ]]; then
        echo -e -n "\n${RED_LIGHT}Aborting, please select another destination drive.${NORMAL}\n\n"
        press_any_key_to_continue
        clear
        break
      elif [[ $yn =~ ${regex_YES} ]]; then
        if grep -q "$user_drive" /proc/mounts; then
          echo -e -n "\nDrive already mounted.\nChanging directory to $HOME and unmounting every partition before wiping...\n"
          cd "$HOME"
          umount --recursive "$(findmnt "$user_drive" | awk -F " " 'FNR == 2 {print $1}')"
          echo -e -n "\nDrive unmounted successfully.\n"
        fi
        echo -e -n "\nWiping the drive...\n\n"
        if wipefs -a "$user_drive"; then
          sync
          echo -e -n "\n${GREEN_LIGHT}Drive successfully wiped.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
          break
        else
          echo -e -n "\n${RED_LIGHT}Something went wrong, please try again.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
          break
        fi
      else
        echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
        press_any_key_to_continue
        clear
      fi
    done
  fi

}

function header_dp {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}       ${GREEN_LIGHT}Disk partitioning${NORMAL}       ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function disk_partitioning {

  if [[ ! -b "$user_drive" ]]; then
    header_dp
    echo -e -n "\n${RED_LIGHT}Please select a valid destination drive before partitioning.${NORMAL}\n\n"
    press_any_key_to_continue
    clear
  else
    while true; do
      clear
      header_dp
      echo -e -n "\nDrive previously selected for partitioning: ${BLUE_LIGHT}$user_drive${NORMAL}.\n\n"
      read -r -p "Do you want to change it? (y/n): " yn
      if [[ $yn =~ ${regex_YES} ]]; then
        echo -e -n "\n${RED_LIGHT}Aborting, please select another destination drive.${NORMAL}\n\n"
        press_any_key_to_continue
        break
      elif [[ $yn =~ ${regex_NO} ]]; then
        if grep -q "$user_drive" /proc/mounts; then
          echo -e -n "\nDrive already mounted.\nChanging directory to $HOME and unmounting every partition before partitioning...\n"
          cd "$HOME"
          umount --recursive "$(findmnt "$user_drive" | awk -F " " 'FNR == 2 {print $1}')"
          echo -e -n "\nDrive unmounted successfully.\n\n"
          press_any_key_to_continue
          clear
        fi
        while true; do
          clear
          header_dp
          echo -e -n "\n${BLUE_LIGHT}Suggested disk layout${NORMAL}:"
          echo -e -n "\n- GPT as partition table for UEFI systems;"
          echo -e -n "\n- Less than 1 GB for /boot/efi as first partition [EFI System];"
          echo -e -n "\n- Rest of the disk for the partition that will be logically partitioned with LVM (/ and /home) [Linux filesystem]."
          echo -e -n "\n\nThose two will be physical partition.\nYou don't need to create a /home partition now because btrfs subvolumes will take care of that.\n"
          echo -e -n "\nDrive selected for partitioning: ${BLUE_LIGHT}$user_drive${NORMAL}\n\n"
          read -r -p "Which tool do you want to use? (fdisk/cfdisk/sfdisk): " tool

          case "$tool" in
          fdisk)
            fdisk "$user_drive"
            sync
            break
            ;;
          cfdisk)
            cfdisk "$user_drive"
            sync
            break
            ;;
          sfdisk)
            sfdisk "$user_drive"
            sync
            break
            ;;
          *)
            echo -e -n "\n${RED_LIGHT}Please select only one of the three suggested tools.${NORMAL}\n\n"
            press_any_key_to_continue
            ;;
          esac
        done

        while true; do
          if [[ $(fdisk -l "$user_drive" | grep Disklabel | awk '{print $3}') =~ ${regex_GPT} ]]; then
            clear
            header_dp
            echo
            lsblk -p "$user_drive"
            echo
            read -r -p "Is this the desired partition table? (y/n): " yn
            if [[ $yn =~ ${regex_YES} ]]; then
              echo -e -n "\n${GREEN_LIGHT}Drive successfully partitioned.${NORMAL}\n\n"
              press_any_key_to_continue
              clear
              break 2
            elif [[ $yn =~ ${regex_NO} ]]; then
              echo -e -n "\n${RED_LIGHT}Please partition your drive again.${NORMAL}\n\n"
              press_any_key_to_continue
              break
            else
              echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
              press_any_key_to_continue
              clear
            fi
          else
            user_drive=''
            clear
            header_dp
            echo -e -n "\n${RED_LIGHT}Please wipe destination drive again and select GPT as partition table.${NORMAL}\n\n"
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
  fi

}

function header_de {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}        ${GREEN_LIGHT}Disk encryption${NORMAL}        ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function disk_encryption {

  if [[ ! -b "$root_partition" ]]; then
    header_de
    echo -e -n "\n${RED_LIGHT}Please select a valid ROOT partition before enabling Full Disk Encryption.${NORMAL}\n\n"
    press_any_key_to_continue
    clear
  else
    if [[ $lvm_yn =~ ${regex_YES} ]] && [[ -b /dev/mapper/"$vg_name"-"$lv_root_name" ]]; then
      header_de
      echo -e -n "\n${RED_LIGHT}In this script is not allowed to encrypt a partition after using LVM.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
    else
      if [[ $encryption_yn =~ ${regex_YES} ]]; then
        while true; do
          header_de
          echo -e -n "\nEncryption is already enabled for partition ${BLUE_LIGHT}$root_partition${NORMAL}."
          echo -e -n "\nDo you want to disable it? (y/n): "
          read -r yn
          if [[ $yn =~ ${regex_YES} ]]; then
            if cryptsetup close /dev/mapper/"${encrypted_name}"; then
              luks_ot=''
              encryption_yn='n'
              encrypted_partition=''
              echo -e -n "\n${RED_LIGHT}Encryption will be disabled.${NORMAL}\n\n"
              press_any_key_to_continue
              clear
              break
            else
              echo -e -n "\n${RED_LIGHT}Something went wrong, please try again.${NORMAL}\n\n"
              press_any_key_to_continue
              clear
              break
            fi
          elif [[ $yn =~ ${regex_NO} ]]; then
            clear
            break
          else
            echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
            press_any_key_to_continue
            clear
          fi
        done
      elif [[ $encryption_yn =~ ${regex_NO} ]]; then
        while true; do
          header_de
          echo -e -n "\nDo you want to set up ${BLUE_LIGHT}Full Disk Encryption${NORMAL}? (y/n): "
          read -r encryption_yn

          if [[ $encryption_yn =~ ${regex_YES} ]]; then
            while true; do
              echo -e -n "\nDestination partition: ${BLUE_LIGHT}$root_partition${NORMAL}.\n"
              echo -e -n "\n${RED_LIGHT}THIS PARTITION WILL BE FORMATTED AND ENCRYPTED, EVERY DATA INSIDE WILL BE LOST.${NORMAL}\n"
              echo -e -n "${RED_LIGHT}Are you sure you want to continue? (y/n):${NORMAL} "
              read -r yn

              if [[ $yn =~ ${regex_NO} ]]; then
                encryption_yn='n'
                echo -e -n "\n${RED_LIGHT}Aborting, please select another ROOT partition.${NORMAL}\n\n"
                press_any_key_to_continue
                clear
                break 2
              elif [[ $yn =~ ${regex_YES} ]]; then
                echo -e -n "\n${GREEN_LIGHT}Correct partition selected.${NORMAL}\n\n"
                press_any_key_to_continue
                clear
                header_de
                echo -e -n "\nThe selected partition will now be encrypted with LUKS version 1 or 2.\n"
                echo -e -n "\n${RED_LIGHT}LUKS version 1${NORMAL}\n"
                echo -e -n "- Can be used by both EFISTUB and GRUB2\n"
                echo -e -n "\n${RED_LIGHT}LUKS version 2${NORMAL}\n"
                echo -e -n "- Can be used only by EFISTUB and it will automatically be selected later.\n"
                echo -e -n "  [GRUB2 LUKS version 2 support with encrypted /boot is still limited: https://savannah.gnu.org/bugs/?55093].\n"

                while true; do
                  echo -e -n "\nWhich LUKS version do you want to use? (1/2): "
                  read -r luks_ot
                  if [[ "$luks_ot" == "1" ]] || [[ "$luks_ot" == "2" ]]; then
                    echo -e -n "\nUsing LUKS version ${BLUE_LIGHT}$luks_ot${NORMAL}.\n\n"
                    if cryptsetup luksFormat --type=luks"$luks_ot" "$root_partition" --debug --verbose; then
                      echo -e -n "\n${GREEN_LIGHT}Partition successfully encrypted.${NORMAL}\n\n"
                      press_any_key_to_continue
                      clear
                      break
                    else
                      echo -e -n "\n${RED_LIGHT}Something went wrong, exiting...${NORMAL}\n\n"
                      kill_script
                    fi
                  else
                    echo -e -n "\n${RED_LIGHT}Please enter 1 or 2.${NORMAL}\n\n"
                    press_any_key_to_continue
                  fi
                done

                while true; do
                  header_de
                  echo -e -n "\nEnter a ${BLUE_LIGHT}name${NORMAL} for the ${BLUE_LIGHT}encrypted partition${NORMAL} without any spaces (i.e. MyEncryptedLinuxPartition).\n"
                  echo -e -n "\nThe name will be used to mount the encrypted partition to ${BLUE_LIGHT}/dev/mapper/[...]${NORMAL} : "
                  read -r encrypted_name
                  if [[ -z "$encrypted_name" ]]; then
                    echo -e -n "\nPlease enter a valid name.\n\n"
                    press_any_key_to_continue
                    clear
                  else
                    while true; do
                      echo -e -n "\nYou entered: ${BLUE_LIGHT}$encrypted_name${NORMAL}.\n\n"
                      read -r -p "Is this the desired name? (y/n): " yn

                      if [[ $yn =~ ${regex_YES} ]]; then
                        echo -e -n "\nPartition will now be mounted as: ${BLUE_LIGHT}/dev/mapper/$encrypted_name${NORMAL}\n\n"
                        if ! cryptsetup open "$root_partition" "$encrypted_name"; then
                          echo -e -n "\n${RED_LIGHT}Something went wrong, exiting...${NORMAL}\n\n"
                          kill_script
                        else
                          encrypted_partition=/dev/mapper/"$encrypted_name"
                          echo -e -n "\n${GREEN_LIGHT}Encrypted partition successfully mounted.${NORMAL}\n\n"
                          press_any_key_to_continue
                          clear
                          break 2
                        fi
                      elif [[ $yn =~ ${regex_NO} ]]; then
                        echo -e -n "\n${RED_LIGHT}Please select another name.${NORMAL}\n\n"
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

                break 2
              else
                echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
                press_any_key_to_continue
              fi
            done

          elif [[ $encryption_yn =~ ${regex_NO} ]]; then
            clear
            break

          else
            echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
            press_any_key_to_continue
            clear
          fi

        done
      fi
    fi
  fi

}

function header_lc {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}   ${GREEN_LIGHT}Logical Volume Management${NORMAL}   ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function lvm_creation {

  if [[ $encryption_yn =~ ${regex_NO} ]] && [[ ! -b "$root_partition" ]]; then
    header_lc
    echo -e -n "\n${RED_LIGHT}Please select a valid ROOT partition before enabling LVM.${NORMAL}\n\n"
    press_any_key_to_continue
    clear
  elif [[ $encryption_yn =~ ${regex_YES} ]] && [[ ! -b "$encrypted_partition" ]]; then
    header_lc
    echo -e -n "\n${RED_LIGHT}Please encrypt a valid ROOT partition before enabling LVM.${NORMAL}\n\n"
    press_any_key_to_continue
    clear
  else
    if [[ $lvm_yn =~ ${regex_YES} ]]; then
      while true; do
        header_de
        if [[ $encryption_yn =~ ${regex_YES} ]]; then
          echo -e -n "\nLVM is already enabled for partition ${BLUE_LIGHT}$encrypted_partition${NORMAL}."
        elif [[ $encryption_yn =~ ${regex_NO} ]]; then
          echo -e -n "\nLVM is already enabled for partition ${BLUE_LIGHT}$root_partition${NORMAL}."
        fi
        echo -e -n "\nDo you want to disable it? (y/n): "
        read -r yn
        if [[ $yn =~ ${regex_YES} ]]; then
          if lvchange -an /dev/mapper/"$vg_name"-"$lv_root_name" && vgchange -an /dev/mapper/"$vg_name"; then
            lvm_yn='n'
            lvm_partition=''
            echo -e -n "\n${RED_LIGHT}LVM will be disabled.${NORMAL}\n\n"
            press_any_key_to_continue
            clear
            break
          else
            echo -e -n "\n${RED_LIGHT}Something went wrong, exiting...${NORMAL}\n\n"
            kill_script
          fi
        elif [[ $yn =~ ${regex_NO} ]]; then
          clear
          break
        else
          echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
        fi
      done
    elif [[ $lvm_yn =~ ${regex_NO} ]]; then

      while true; do

        header_lc

        echo -e -n "\nWith LVM will be easier in the future to add more space"
        echo -e -n "\nto the ROOT partition without formatting the whole system.\n"
        echo -e -n "\nDo you want to use ${BLUE_LIGHT}LVM${NORMAL}? (y/n): "
        read -r lvm_yn

        if [[ $lvm_yn =~ ${regex_YES} ]]; then

          clear

          while true; do

            header_lc
            echo -e -n "\nCreating logical partitions wih LVM.\n"
            echo -e -n "\nEnter a ${BLUE_LIGHT}name${NORMAL} for the ${BLUE_LIGHT}Volume Group${NORMAL} without any spaces (i.e. MyLinuxVolumeGroup).\n"
            echo -e -n "\nThe name will be used to mount the Volume Group as: ${BLUE_LIGHT}/dev/mapper/[...]${NORMAL} : "
            read -r vg_name

            if [[ -z "$vg_name" ]]; then
              echo -e -n "\n${RED_LIGHT}Please enter a valid name.${NORMAL}\n\n"
              press_any_key_to_continue
              clear
            else
              while true; do
                echo -e -n "\nYou entered: ${BLUE_LIGHT}$vg_name${NORMAL}.\n\n"
                read -r -p "Is this the desired name? (y/n): " yn

                if [[ $yn =~ ${regex_YES} ]]; then
                  echo -e -n "\n\nVolume Group will now be created and mounted as: ${BLUE_LIGHT}/dev/mapper/$vg_name${NORMAL}\n\n"
                  if [[ $encryption_yn =~ ${regex_YES} ]]; then
                    if ! vgcreate "$vg_name" "$encrypted_partition"; then
                      echo -e -n "\n${RED_LIGHT}Something went wrong, exiting...${NORMAL}\n\n"
                      kill_script
                    fi
                  elif [[ $encryption_yn =~ ${regex_NO} ]]; then
                    if ! vgcreate "$vg_name" "$root_partition"; then
                      echo -e -n "\n${RED_LIGHT}Something went wrong, exiting...${NORMAL}\n\n"
                      kill_script
                    fi
                  fi
                  echo
                  press_any_key_to_continue
                  clear
                  break 2
                elif [[ $yn =~ ${regex_NO} ]]; then
                  echo -e -n "\n${RED_LIGHT}Please select another name${NORMAL}.\n\n"
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

          while true; do

            header_lc
            echo -e -n "\nEnter a ${BLUE_LIGHT}name${NORMAL} for the ${BLUE_LIGHT}Logical Volume${NORMAL} without any spaces (i.e. MyLinuxLogicVolume)."
            echo -e -n "\nIts size will be the entire partition previosly selected.\n"
            echo -e -n "\nThe name will be used to mount the Logical Volume as: ${BLUE_LIGHT}/dev/mapper/$vg_name-[...]${NORMAL} : "
            read -r lv_root_name

            if [[ -z "$lv_root_name" ]]; then
              echo -e -n "\n${RED_LIGHT}Please enter a valid name.${NORMAL}\n\n"
              press_any_key_to_continue
              clear
            else
              while true; do
                echo -e -n "\nYou entered: ${BLUE_LIGHT}$lv_root_name${NORMAL}.\n\n"
                read -r -p "Is this correct? (y/n): " yn

                if [[ $yn =~ ${regex_YES} ]]; then
                  echo -e -n "\nLogical Volume ${BLUE_LIGHT}$lv_root_name${NORMAL} will now be created.\n\n"
                  if lvcreate --name "$lv_root_name" -l +100%FREE "$vg_name"; then
                    echo
                    read -n 1 -r -p "[Press any key to continue...]" _key
                    lvm_partition=/dev/mapper/"$vg_name"-"$lv_root_name"
                    clear
                    break 3
                  else
                    echo -e -n "\n${RED_LIGHT}Something went wrong, exiting...${NORMAL}\n\n"
                    kill_script
                  fi
                elif [[ $yn =~ ${regex_NO} ]]; then
                  echo -e -n "\n${RED_LIGHT}Please select another name${NORMAL}.\n\n"
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

        elif [[ $lvm_yn =~ ${regex_NO} ]]; then
          clear
          break

        else
          echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
        fi

      done
    fi

  fi

}

function header_al {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}       ${GREEN_LIGHT}Filesystem labels${NORMAL}       ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function assign_labels {

  header_al
  echo -e -n "\nPlease enter a label for ${BLUE_LIGHT}EFI partition${NORMAL}: "
  read -r boot_label

  echo -e -n "\nPlease enter a label for ${BLUE_LIGHT}ROOT partition${NORMAL}: "
  read -r root_label

}

function detect_final_drive {

  if [[ $encryption_yn =~ ${regex_YES} ]]; then
    if [[ $lvm_yn =~ ${regex_YES} ]]; then
      final_drive=$lvm_partition
    elif [[ $lvm_yn =~ ${regex_NO} ]]; then
      final_drive=$encrypted_partition
    fi
  elif [[ $encryption_yn =~ ${regex_NO} ]]; then
    if [[ $lvm_yn =~ ${regex_YES} ]]; then
      final_drive=$lvm_partition
    elif [[ $lvm_yn =~ ${regex_NO} ]]; then
      final_drive=$root_partition
    fi
  fi

}

function header_fcis {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}        ${GREEN_LIGHT}System creation${NORMAL}        ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function format_create_install_system {

  detect_final_drive

  if [[ -z "$final_drive" ]] || [[ -z "$boot_label" ]] || [[ -z "$root_label" ]]; then
    header_fcis
    echo -e -n "\n${RED_LIGHT}Please complete at least steps 3, 6, 7 and 10 before installing the system.${NORMAL}\n\n"
    press_any_key_to_continue
    clear
  elif ! ping -c 1 8.8.8.8 &>/dev/null; then
    header_fcis
    echo -e -n "\n${RED_LIGHT}Installation requires internet connection.${NORMAL}\n\n"
    press_any_key_to_continue
    clear
  else
    if [[ "$boot_partition" == "$root_partition" ]]; then
      header_fcis
      echo -e -n "\n${RED_LIGHT}EFI and ROOT partitions must not be the same.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
    else
      while true; do
        header_fcis
        echo -e -n "\n${RED_LIGHT}BY SELECTING YES, EVERYTHING WILL BE FORMATTED, EVERY DATA WILL BE LOST.${NORMAL}\n"
        echo -e -n "${RED_LIGHT}Are you sure you want to continue? (y/n):${NORMAL} "
        read -r yn

        if [[ $yn =~ ${regex_NO} ]]; then
          clear
          break
        elif [[ $yn =~ ${regex_YES} ]]; then

          # Format partition
          clear
          header_fcis
          echo -e -n "\nFormatting ${BLUE_LIGHT}EFI partition${NORMAL} as ${BLUE_LIGHT}FAT32${NORMAL}...\n\n"
          if grep -q "$boot_partition" /proc/mounts; then
            echo -e -n "\nPartition already mounted.\nChanging directory to $HOME and unmounting it before formatting...\n"
            cd "$HOME"
            umount --recursive "$(findmnt "$boot_partition" | awk -F " " 'FNR == 2 {print $1}')"
            echo -e -n "\nDrive unmounted successfully.\n\n"
            press_any_key_to_continue
          fi
          if mkfs.vfat -n "$boot_label" -F 32 "$boot_partition"; then
            sync
            echo -e -n "\n${GREEN_LIGHT}EFI partition successfully formatted.${NORMAL}\n\n"
            press_any_key_to_continue
          else
            echo -e -n "\n${RED_LIGHT}Something went wrong, exiting...${NORMAL}\n\n"
            kill_script
          fi

          clear
          header_fcis
          echo -e -n "\nRoot partition will be formatted as ${BLUE_LIGHT}BTRFS${NORMAL}...\n\n"
          if mkfs.btrfs --force -L "$root_label" "$final_drive"; then
            sync
            echo -e -n "\n${GREEN_LIGHT}ROOT partition successfully formatted.${NORMAL}\n\n"
            press_any_key_to_continue
          else
            echo -e -n "\n${RED_LIGHT}Something went wrong, exiting...${NORMAL}\n\n"
            kill_script
          fi

          # Create BTRFS subvolumes
          clear
          header_fcis

          if [[ -n $(lsblk "$final_drive" --discard |
            awk -F " " 'FNR == 2 {print $3}') ]] && [[ -n $(lsblk "$final_drive" --discard |
              awk -F " " 'FNR == 2 {print $4}') ]]; then
            hdd_ssd=ssd
          else
            hdd_ssd=hdd
          fi

          echo -e -n "\nBTRFS subvolumes will now be created with following options:\n"
          echo -e -n "- rw\n"
          echo -e -n "- noatime\n"
          if [[ "$hdd_ssd" == "ssd" ]]; then
            echo -e -n "- discard=async\n"
          fi
          echo -e -n "- compress-force=zstd\n"
          echo -e -n "- space_cache=v2\n"
          echo -e -n "- commit=120\n"

          echo -e -n "\nSubvolumes that will be created:\n"
          echo -e -n "- /@\n"
          echo -e -n "- /@home\n"
          echo -e -n "- /@snapshots\n"
          echo -e -n "- /@swap\n"
          echo -e -n "- /var/cache/xbps\n"
          echo -e -n "- /var/tmp\n"
          echo -e -n "- /var/log\n\n"

          press_any_key_to_continue

          if grep -q /mnt /proc/mounts; then
            echo -e -n "Everything mounted to /mnt will now be unmounted...\n"
            cd "$HOME"
            umount --recursive /mnt
            echo -e -n "\nDone.\n\n"
            press_any_key_to_continue
          fi

          echo -e -n "\nCreating BTRFS subvolumes and mounting them to /mnt...\n"

          if [[ "$hdd_ssd" == "ssd" ]]; then
            export BTRFS_OPT=rw,noatime,discard=async,compress-force=zstd,space_cache=v2,commit=120
          elif [[ "$hdd_ssd" == "hdd" ]]; then
            export BTRFS_OPT=rw,noatime,compress-force=zstd,space_cache=v2,commit=120
          fi
          mount -o "$BTRFS_OPT" "$final_drive" /mnt
          btrfs subvolume create /mnt/@
          btrfs subvolume create /mnt/@home
          btrfs subvolume create /mnt/@snapshots
          btrfs subvolume create /mnt/@swap
          umount /mnt
          mount -o "$BTRFS_OPT",subvol=@ "$final_drive" /mnt
          mkdir /mnt/home
          mount -o "$BTRFS_OPT",subvol=@home "$final_drive" /mnt/home/
          mkdir /mnt/swap
          mount -o "$BTRFS_OPT",subvol=@swap "$final_drive" /mnt/swap/
          mkdir -p /mnt/var/cache
          btrfs subvolume create /mnt/var/cache/xbps
          btrfs subvolume create /mnt/var/tmp
          btrfs subvolume create /mnt/var/log

          echo -e -n "\n${GREEN_LIGHT}Done.${NORMAL}\n\n"
          press_any_key_to_continue

          # Install base system

          while true; do
            clear
            header_fcis
            echo -e -n "\nSelect which ${BLUE_LIGHT}architecture${NORMAL} do you want to use:\n\n"
            select user_arch in x86_64 x86_64-musl; do
              case "$user_arch" in
              x86_64)
                echo -e -n "\n${BLUE_LIGHT}$user_arch${NORMAL} selected.\n"
                ARCH="$user_arch"
                export REPO=https://repo-default.voidlinux.org/current
                break 2
                ;;
              x86_64-musl)
                echo -e -n "\n${BLUE_LIGHT}$user_arch${NORMAL} selected.\n"
                ARCH="$user_arch"
                export REPO=https://repo-default.voidlinux.org/current/musl
                break 2
                ;;
              *)
                echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
                press_any_key_to_continue
                break
                ;;
              esac
            done
          done

          echo -e -n "\nCopying RSA keys...\n"
          mkdir -p /mnt/var/db/xbps/keys
          cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/

          echo -e -n "\nInstalling base system...\n\n"
          press_any_key_to_continue
          echo

          if ! XBPS_ARCH="$ARCH" xbps-install -Suvy xbps; then
            echo -e -n "\n${RED_LIGHT}Something went wrong, killing script...${NORMAL}\n\n"
            kill_script
          fi
          if ! XBPS_ARCH="$ARCH" xbps-install -Suvy -r /mnt -R "$REPO" base-system btrfs-progs cryptsetup grub-x86_64-efi \
            efibootmgr lvm2 grub-btrfs grub-btrfs-runit NetworkManager bash-completion nano gcc apparmor git curl \
            util-linux tar coreutils binutils xtools fzf xmirror plocate ictree xkeyboard-config ckbcomp void-repo-nonfree; then
            echo -e -n "\n${RED_LIGHT}Something went wrong, killing script...${NORMAL}\n\n"
            kill_script
          fi
          if [[ "$XBPS_ARCH" == "x86_64" ]]; then
            if ! XBPS_ARCH="$ARCH" xbps-install -Suvy -r /mnt -R "$REPO" void-repo-multilib void-repo-multilib-nonfree; then
              echo -e -n "\n${RED_LIGHT}Something went wrong, killing script...${NORMAL}\n\n"
              kill_script
            fi
          fi
          if ! XBPS_ARCH="$ARCH" xbps-install -Suvy -r /mnt -R "$REPO"; then
            echo -e -n "\n${RED_LIGHT}Something went wrong, killing script...${NORMAL}\n\n"
            kill_script
          fi
          if [[ "$XBPS_ARCH" == "x86_64" ]] && grep -m 1 "model name" /proc/cpuinfo | grep --ignore-case "intel" &>/dev/null; then
            if ! XBPS_ARCH="$ARCH" xbps-install -Suvy -r /mnt -R "$REPO" intel-ucode; then
              echo -e -n "\n${RED_LIGHT}Something went wrong, killing script...${NORMAL}\n\n"
              kill_script
            fi
          fi

          echo -e -n "\nMounting folders for chroot...\n"
          mount -t proc none /mnt/proc
          mount -t sysfs none /mnt/sys
          mount --rbind /dev /mnt/dev
          mount --rbind /run /mnt/run
          mount --rbind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars/

          echo -e -n "\nCopying /etc/resolv.conf...\n"
          cp -L /etc/resolv.conf /mnt/etc/

          if cp -L /etc/NetworkManager/system-connections/* /mnt/etc/NetworkManager/system-connections/ &>/dev/null; then
            echo -e -n "\nCopying /etc/NetworkManager/system-connections/...\n"
          fi

          # Chrooting
          echo -e -n "\nChrooting...\n\n"
          press_any_key_to_continue
          cp "$HOME"/chroot.sh /mnt/root/

          BTRFS_OPT="$BTRFS_OPT" boot_partition="$boot_partition" encryption_yn="$encryption_yn" luks_ot="$luks_ot" root_partition="$root_partition" \
            encrypted_name="$encrypted_name" lvm_yn="$lvm_yn" vg_name="$vg_name" lv_root_name="$lv_root_name" user_drive="$user_drive" final_drive="$final_drive" \
            user_keyboard_layout="$user_keyboard_layout" hdd_ssd="$hdd_ssd" void_packages_repo="$void_packages_repo" ARCH="$ARCH" BLUE_LIGHT="$BLUE_LIGHT" \
            BLUE_LIGHT_FIND="$BLUE_LIGHT_FIND" GREEN_DARK="$GREEN_DARK" GREEN_LIGHT="$GREEN_LIGHT" NORMAL="$NORMAL" NORMAL_FIND="$NORMAL_FIND" RED_LIGHT="$RED_LIGHT" BLACK_FG_WHITE_BG=$BLACK_FG_WHITE_BG regex_YES=$regex_YES regex_NO=$regex_NO regex_BACK=$regex_BACK regex_EFISTUB=$regex_EFISTUB regex_GRUB2=$regex_GRUB2 \
            regex_ROOT=$regex_ROOT \
            chroot /mnt/ /bin/bash "$HOME"/chroot.sh

          clear
          header_fcis
          echo -e -n "\nCleaning...\n"
          rm -f /mnt/root/chroot.sh

          echo -e -n "\nUnmounting partitions...\n\n"
          if findmnt /mnt &>/dev/null; then
            umount --recursive /mnt
          fi

          if [[ $lvm_yn =~ ${regex_YES} ]]; then
            lvchange -an /dev/mapper/"$vg_name"-"$lv_root_name"
            vgchange -an /dev/mapper/"$vg_name"
          fi

          if [[ $encryption_yn =~ ${regex_YES} ]]; then
            cryptsetup close /dev/mapper/"$encrypted_name"
          fi

          echo
          press_any_key_to_continue
          clear

          outro

        else
          echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
          press_any_key_to_continue
          clear
        fi
      done
    fi
  fi
}

function outro {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}    ${GREEN_LIGHT}Installation completed${NORMAL}     ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

  echo -e -n "\nAfter rebooting into the new installed system, be sure to:\n"
  echo -e -n "- If you plan yo use snapper, after installing it and creating a configuration for / [root],\n  uncomment the line relative to /.snapshots folder\n"
  echo -e -n "\n${GREEN_LIGHT}Everything's done, goodbye.${NORMAL}\n\n"

  press_any_key_to_continue
  clear
  exit 0

}

# Main

function header_main {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #   ${GREEN_LIGHT}Void Linux Installer Menu${NORMAL}   ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function main {

  while true; do

    header_main

    echo -e -n "\n1) Set keyboard layout\t\t\t......\tKeyboard layout: "
    current_xkeyboard_layout=$(setxkbmap -query 2>/dev/null | grep layout | awk '{print $2}')
    if [[ -n "${current_xkeyboard_layout}" ]] || [[ -n "${user_keyboard_layout}" ]]; then
      echo -e -n "\t${GREEN_LIGHT}${current_xkeyboard_layout:-${user_keyboard_layout}}${NORMAL}"
      user_keyboard_layout="${current_xkeyboard_layout:-${user_keyboard_layout}}"
    else
      echo -e -n "${RED_LIGHT}\tnone${NORMAL}"
    fi

    echo -e -n "\n2) Set up internet connection\t\t......\tConnection status: "
    if ping -c 1 8.8.8.8 &>/dev/null; then
      echo -e -n "${GREEN_LIGHT}\tconnected${NORMAL}"
    else
      echo -e -n "${RED_LIGHT}\tnot connected${NORMAL}"
    fi

    echo

    echo -e -n "\n3) Select destination drive\t\t......\tDrive selected: "
    if [[ -b "$user_drive" ]]; then
      echo -e -n "${GREEN_LIGHT}\t${user_drive}${NORMAL}"
    else
      echo -e -n "${RED_LIGHT}\tnone${NORMAL}"
    fi

    echo -e -n "\n4) Wipe destination drive\t\t......\tDrive selected: "
    if [[ -b "$user_drive" ]]; then
      echo -e -n "${GREEN_LIGHT}\t${user_drive}${NORMAL}"
    else
      echo -e -n "${RED_LIGHT}\tnone${NORMAL}"
    fi

    echo -e -n "\n5) Partition destination drive\t\t......\tDrive selected: "
    if [[ -b "$user_drive" ]]; then
      echo -e -n "${GREEN_LIGHT}\t${user_drive}${NORMAL}"
    else
      echo -e -n "${RED_LIGHT}\tnone${NORMAL}"
    fi

    echo

    echo -e -n "\n6) Select EFI partition\t\t\t......\tPartition selected: "
    if [[ -b "$boot_partition" ]]; then
      echo -e -n "${GREEN_LIGHT}\t${boot_partition}${NORMAL}"
    else
      echo -e -n "${RED_LIGHT}\tnone${NORMAL}"
    fi

    echo -e -n "\n7) Select ROOT partition\t\t......\tPartition selected: "
    if [[ -b "$root_partition" ]]; then
      echo -e -n "${GREEN_LIGHT}\t${root_partition}${NORMAL}"
    else
      echo -e -n "${RED_LIGHT}\tnone${NORMAL}"
    fi

    echo

    echo -e -n "\n8) Set up Full Disk Encryption\t\t......\tEncryption: "
    if [[ $encryption_yn =~ ${regex_YES} ]]; then
      echo -e -n "${GREEN_LIGHT}\t\tYES${NORMAL}"
      echo -e -n "\n\t\t\t\t\t......\tEncrypted partition:\t${GREEN_LIGHT}${encrypted_partition}${NORMAL}"
    elif [[ $encryption_yn =~ ${regex_NO} ]]; then
      echo -e -n "${RED_LIGHT}\t\tNO${NORMAL}"
      echo -e -n "\n\t\t\t\t\t......\tEncrypted partition:\t${RED_LIGHT}none${NORMAL}"
    fi

    echo -e -n "\n9) Set up Logical Volume Management\t......\tLVM: "
    if [[ $lvm_yn =~ ${regex_YES} ]]; then
      echo -e -n "${GREEN_LIGHT}\t\t\tYES${NORMAL}"
      echo -e -n "\n\t\t\t\t\t......\tLVM partition\t\t${GREEN_LIGHT}${lvm_partition}${NORMAL}"
    elif [[ $lvm_yn =~ ${regex_NO} ]]; then
      echo -e -n "${RED_LIGHT}\t\t\tNO${NORMAL}"
      echo -e -n "\n\t\t\t\t\t......\tLVM partition:\t\t${RED_LIGHT}none${NORMAL}"
    fi

    echo

    echo -e -n "\n10) Set up partition labels: "
    if [[ -n $boot_label ]]; then
      echo -e -n "\t\t......\tEFI label\t\t${GREEN_LIGHT}${boot_label}${NORMAL}"
    else
      echo -e -n "\t\t......\tEFI label\t\t${RED_LIGHT}none${NORMAL}"
    fi
    if [[ -n $root_label ]]; then
      echo -e -n "\n\t\t\t\t\t......\tROOT label\t\t${GREEN_LIGHT}${root_label}${NORMAL}"
    else
      echo -e -n "\n\t\t\t\t\t......\tROOT label\t\t${RED_LIGHT}none${NORMAL}"
    fi

    echo

    echo -e -n "\n11) Install base system and chroot inside"

    echo

    echo -e -n "\nx) ${RED_LIGHT}Quit and unmount everything.${NORMAL}\n"

    echo -e -n "\nUser selection: "
    read -r menu_selection

    case "${menu_selection}" in
    1)
      clear
      set_keyboard_layout
      clear
      ;;
    2)
      clear
      connect_to_internet
      clear
      ;;
    3)
      clear
      drive_partition_selection='3'
      select_destination
      drive_partition_selection='0'
      clear
      ;;
    4)
      clear
      disk_wiping
      clear
      ;;
    5)
      clear
      disk_partitioning
      clear
      ;;
    6)
      clear
      drive_partition_selection='6'
      select_destination
      drive_partition_selection='0'
      clear
      ;;
    7)
      clear
      drive_partition_selection='7'
      select_destination
      drive_partition_selection='0'
      clear
      ;;
    8)
      clear
      disk_encryption
      clear
      ;;
    9)
      clear
      lvm_creation
      clear
      ;;
    10)
      clear
      assign_labels
      clear
      ;;
    11)
      clear
      format_create_install_system
      clear
      ;;
    x)
      kill_script
      ;;
    *)
      echo -e -n "\n${RED_LIGHT}Not a valid input.${NORMAL}\n\n"
      press_any_key_to_continue
      clear
      ;;
    esac
  done

}

check_if_bash
check_if_run_as_root
check_if_uefi
create_chroot_script
intro
main
