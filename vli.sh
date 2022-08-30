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

user_drive=''
encryption_yn=''
luks_ot=''
encrypted_partition=''
encrypted_name=''
lvm_yn=''
vg_name=''
lv_root_name=''
final_drive=''
boot_partition=''
hdd_ssd=''
user_keyboard_layout=''

# Constants

void_packages_repo="https://github.com/void-linux/void-packages.git"

# Colours

BLUE_LIGHT="\e[1;34m"
BLUE_LIGHT_FIND="\033[1;34m"
GREEN_DARK="\e[0;32m"
GREEN_LIGHT="\e[1;32m"
NORMAL="\e[0m"
NORMAL_FIND="\033[0m"
RED_LIGHT="\e[1;31m"

# Functions

function kill_script {

  echo -e -n "\n\n${RED_LIGHT}Kill signal captured.\nUnmonting what should have been mounted, cleaning and closing everything...${NORMAL}\n\n"
  
  if findmnt /mnt &> /dev/null ; then
    umount --recursive /mnt
  fi
  
  if [[ "$lvm_yn" == "y" ]] || [[ "$lvm_yn" == "Y" ]] ; then
    lvchange -an /dev/mapper/"$vg_name"-"$lv_root_name"
    vgchange -an /dev/mapper/"$vg_name"
  fi

  if [[ "$encryption_yn" == "y" ]] || [[ "$encryption_yn" == "Y" ]] ; then
    cryptsetup close /dev/mapper/"$encrypted_name"
  fi

  if [[ -f "$HOME"/chroot.sh ]] ; then
    rm -f "$HOME"/chroot.sh
  fi

  if [[ -f "$HOME"/btrfs_map_physical.c ]] ; then
    rm -f "$HOME"/btrfs_map_physical.c
  fi

  echo -e -n "\n${BLUE_LIGHT}Everything's done, quitting.${NORMAL}\n\n"
  exit 1

}

function check_if_bash {

  if [[ "$(ps -p $$ | tail -1 | awk '{print $NF}')" != "bash" ]] ; then
    echo -e -n "Please run this script with bash shell: \"bash vli.sh\".\n"
    exit 1
  fi

}

function check_if_run_as_root {

  if [[ "$UID" != "0" ]] ; then
    echo -e -n "Please run this script as root.\n"
    exit 1
  fi

}

function check_if_uefi {

  if ! grep efivar -q /proc/mounts ; then
    if ! mount -t efivarfs efivarfs /sys/firmware/efi/efivars/ &> /dev/null ; then
      echo -e -n "Please run this script only on a UEFI system."
      exit 1
    fi
  fi

}

function create_chroot_script {

  if [[ -f "$HOME"/chroot.sh ]] ; then
    rm -f "$HOME"/chroot.sh
  fi

cat >> "$HOME"/chroot.sh << 'EndOfScript'
#! /bin/bash

# Variables

newuser_yn=''

# Functions

# Source: https://www.reddit.com/r/voidlinux/comments/jlkv1j/xs_quick_install_tool_for_void_linux/
function xs {

  xpkg -a | fzf -m --preview 'xq {1}' --preview-window=right:66%:wrap | xargs -ro xi

}

function initial_configuration {

  clear
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}     ${GREEN_LIGHT}Initial configuration${NORMAL}     ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

  echo -e -n "\nSetting root password:\n"
  while true ; do
    echo
    passwd root
    if [[ "$?" == "0" ]] ; then
      break
    else
      echo -e -n "\n${RED_LIGHT}Something went wrong, please try again.${NORMAL}\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      echo
    fi
  done
  
  echo -e -n "\nSetting root permissions...\n"
  chown root:root /
  chmod 755 /

  echo -e -n "\nEnabling wheel group to use sudo...\n"
  echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-wheel

  echo -e -n "\nExporting variables that will be used for fstab...\n"
  export LUKS_UUID=$(blkid -s UUID -o value "$encrypted_partition")
  export ROOT_UUID=$(blkid -s UUID -o value "$final_drive")
  
  echo -e -n "\nWriting fstab...\n"
  sed -i '/tmpfs/d' /etc/fstab

cat << EOF >> /etc/fstab

# Root subvolume
UUID=$ROOT_UUID / btrfs $BTRFS_OPT,subvol=@ 0 1

# Home subvolume
UUID=$ROOT_UUID /home btrfs $BTRFS_OPT,subvol=@home 0 2

# Snapshots subvolume, uncomment the following line after creating a config for root [/] in snapper
#UUID=$ROOT_UUID /.snapshots btrfs $BTRFS_OPT,subvol=@snapshots 0 2

# TMPfs
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
EOF

  echo -e -n "\nAdding needed dracut configuration files...\n"
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

function header_ib {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}    ${GREEN_LIGHT}Bootloader installation${NORMAL}    ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  
}

function install_bootloader {

  while true ; do

    if [[ "$luks_ot" == "2" ]] ; then
      header_ib
      echo -e -n "\nLUKS version $luks_ot was previously selected.\n${BLUE_LIGHT}EFISTUB${NORMAL} will be used as bootloader.\n\n"
      bootloader="EFISTUB"
      read -n 1 -r -p "[Press any key to continue...]" key
      echo
    else
      header_ib
      echo -e -n "\nSelect which ${BLUE_LIGHT}bootloader${NORMAL} do you want to use (EFISTUB, GRUB2): "
      read -r bootloader
    fi

    if [[ "$bootloader" == "EFISTUB" ]] || [[ "$bootloader" == "efistub" ]] ; then
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
      if [[ "$encryption_yn" == "y" ]] || [[ "$encryption_yn" == "Y" ]] ; then
        sed -i "/# OPTIONS=/s/.*/OPTIONS=\"loglevel=4 rd.auto=1 rd.luks.name=$LUKS_UUID=$encrypted_name\"/" /etc/default/efibootmgr-kernel-hook
        if [[ "$hdd_ssd" == "ssd" ]] ; then
          sed -i "/OPTIONS=/s/\"$/ rd.luks.allow-discards=$LUKS_UUID&/" /etc/default/efibootmgr-kernel-hook
        fi
      elif { [[ "$encryption_yn" == "n" ]] || [[ "$encryption_yn" == "N" ]]; } && { [[ "$lvm" == "y" ]] || [[ "$lvm_yn" == "Y" ]]; } ; then
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

      read -n 1 -r -p "[Press any key to continue...]" key
      break

    elif [[ "$bootloader" == "GRUB2" ]] || [[ "$bootloader" == "grub2" ]] ; then
      echo -e -n "\nBootloader selected: ${BLUE_LIGHT}$bootloader${NORMAL}.\n"
      if [[ "$encryption_yn" == "y" ]] || [[ "$encryption_yn" == "Y" ]] ; then
        echo -e -n "\nEnabling CRYPTODISK in GRUB...\n"
        echo -e -n "\nGRUB_ENABLE_CRYPTODISK=y\n" >> /etc/default/grub
        sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ rd.auto=1 rd.luks.name=$LUKS_UUID=$encrypted_name&/" /etc/default/grub
        if [[ "$hdd_ssd" == "ssd" ]] ; then
          sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ rd.luks.allow-discards=$LUKS_UUID&/" /etc/default/grub
        fi
     elif { [[ "$encryption_yn" == "n" ]] || [[ "$encryption_yn" == "N" ]]; } && { [[ "$lvm" == "y" ]] || [[ "$lvm_yn" == "Y" ]]; } ; then
        sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ rd.auto=1&/" /etc/default/grub
      fi

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
              if [[ "$encryption_yn" == "y" ]] || [[ "$encryption_yn" == "Y" ]] ; then
                echo -e -n "\n\nGenerating random key to avoid typing password twice at boot...\n\n"
                dd bs=512 count=4 if=/dev/random of=/boot/volume.key
                echo -e -n "\nRandom key generated, unlocking the encrypted partition...\n"
                while true ; do
                  echo
                  cryptsetup luksAddKey "$encrypted_partition" /boot/volume.key
                  if [[ "$?" == "0" ]] ; then
                    break
                  else
                    echo -e -n "\n${RED_LIGHT}Something went wrong, please try again.${NORMAL}\n\n"
                    read -n 1 -r -p "[Press any key to continue...]" key
                    echo
                  fi
                done
                chmod 000 /boot/volume.key
                chmod -R g-rwx,o-rwx /boot
                echo -e -n "\nAdding random key to /etc/crypttab...\n"
                echo -e "\n$encrypted_name UUID=$LUKS_UUID /boot/volume.key luks\n" >> /etc/crypttab
                echo -e -n "\nAdding random key to dracut configuration files...\n"
                echo -e "install_items+=\" /boot/volume.key /etc/crypttab \"" >> /etc/dracut.conf.d/10-crypt.conf
                echo -e -n "\nGenerating new dracut initramfs...\n\n"
                read -n 1 -r -p "[Press any key to continue...]" key
                echo
                dracut --regenerate-all --force --hostonly
              fi
              echo -e -n "\n\nInstalling GRUB on ${BLUE_LIGHT}/boot/efi${NORMAL} partition with ${BLUE_LIGHT}$bootloader_id${NORMAL} as bootloader-id...\n\n"
              mkdir -p /boot/efi
              mount -o rw,noatime "$boot_partition" /boot/efi/
              grub-install --target=x86_64-efi --boot-directory=/boot --efi-directory=/boot/efi --bootloader-id="$bootloader_id" --recheck
              break 3
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

    else
      echo -e -n "\nPlease select a valid bootloader.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
    fi

  done

  if { [[ "$lvm_yn" == "y" ]] || [[ "$lvm_yn" == "Y" ]]; } && [[ "$hdd_ssd" == "ssd" ]] ; then
    echo -e -n "\n\nEnabling SSD trim for LVM...\n"
    sed -i 's/issue_discards = 0/issue_discards = 1/' /etc/lvm/lvm.conf
  fi

  export UEFI_UUID=$(blkid -s UUID -o value "$boot_partition")
  echo -e -n "\nWriting EFI partition to /etc/fstab...\n"
  if [[ "$bootloader" == "EFISTUB" ]] || [[ "$bootloader" == "efistub" ]] ; then
    echo -e "\n# EFI partition\nUUID=$UEFI_UUID /boot vfat defaults,noatime 0 2" >> /etc/fstab
  elif [[ "$bootloader" == "GRUB2" ]] || [[ "$bootloader" == "grub2" ]] ; then
    echo -e "\n# EFI partition\nUUID=$UEFI_UUID /boot/efi vfat defaults,noatime 0 2" >> /etc/fstab
  fi

  echo -e -n "\nBootloader ${BLUE_LIGHT}$bootloader${NORMAL} successfully installed.\n\n"
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
          mkswap --label SwapFile /var/swap/swapfile
          swapon /var/swap/swapfile
          gcc -O2 "$HOME"/btrfs_map_physical.c -o "$HOME"/btrfs_map_physical
          RESUME_OFFSET=$(($("$HOME"/btrfs_map_physical /var/swap/swapfile | awk -F " " 'FNR == 2 {print $NF}')/$(getconf PAGESIZE)))
          if [[ "$bootloader" == "EFISTUB" ]] || [[ "$bootloader" == "efistub" ]] ; then
            sed -i "/OPTIONS=/s/\"$/ resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET&/" /etc/default/efibootmgr-kernel-hook
          elif [[ "$bootloader" == "GRUB2" ]] || [[ "$bootloader" == "grub2" ]] ; then
            sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET&/" /etc/default/grub
          fi
          echo -e "\n# SwapFile\n/var/swap/swapfile none swap defaults 0 0" >> /etc/fstab
          echo -e -n "\nEnabling zswap...\n"
          echo "add_drivers+=\" lz4hc lz4hc_compress z3fold \"" >> /etc/dracut.conf.d/40-add_zswap_drivers.conf
          echo -e -n "\nRegenerating dracut initramfs...\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          echo
          dracut --regenerate-all --force --hostonly
          if [[ "$bootloader" == "EFISTUB" ]] || [[ "$bootloader" == "efistub" ]] ; then
            sed -i "/OPTIONS=/s/\"$/ zswap.enabled=1 zswap.max_pool_percent=25 zswap.compressor=lz4hc zswap.zpool=z3fold&/" /etc/default/efibootmgr-kernel-hook
            echo -e -n "\nReconfiguring kernel...\n\n"
            kernelver_pre=$(ls /lib/modules/)
            kernelver=$(echo ${kernelver_pre%.*})
            xbps-reconfigure -f linux"$kernelver"
          elif [[ "$bootloader" == "GRUB2" ]] || [[ "$bootloader" == "grub2" ]] ; then
            sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ zswap.enabled=1 zswap.max_pool_percent=25 zswap.compressor=lz4hc zswap.zpool=z3fold&/" /etc/default/grub
            echo -e -n "\nUpdating grub...\n\n"
            update-grub
          fi
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

function header_iap {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}  ${GREEN_LIGHT}Install additional packages${NORMAL}  ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function install_additional_packages {

while true ; do

    header_iap

    echo -e -n "\nDo you want to install any additional package in your system? (y/n): "
    read -n 1 -r yn
  
    if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then

      echo -e -n "\n\nPlease mark all the packages you want to install with [TAB] key.\nPress [ENTER] key when you're done to install the selected packages\nor press [ESC] key to abort the operation.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
  
      xs

      echo
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
    
    elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
      echo -e -n "\n\nNo additional packages were installed.\n\n"
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

function header_eds {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}            ${GREEN_LIGHT}Chroot${NORMAL}             ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######${NORMAL}    ${GREEN_LIGHT}Enable/disable services${NORMAL}    ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function enable_disable_services {

  header_eds

  echo -e -n "\nEnabling internet service at first boot...\n"
  ln -s /etc/sv/dbus /etc/runit/runsvdir/default/
  ln -s /etc/sv/NetworkManager /etc/runit/runsvdir/default/

  echo -e -n "\nEnabling grub snapshot service at first boot...\n\n"
  ln -s /etc/sv/grub-btrfs /etc/runit/runsvdir/default/

  read -n 1 -r -p "[Press any key to continue...]" key
  clear

  while true ; do

    header_eds
    echo -e -n "\nDo you want to enable any additional service in your system? (y/n): "
    read -n 1 -r yn
  
    if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then

      while true ; do

        clear
        header_eds
        echo -e -n "\nListing all the services that could be enabled...\n"
        ls --almost-all --color=always /etc/sv/

        echo -e -n "\nListing all the services that are already enabled...\n"
        ls --almost-all --color=always /etc/runit/runsvdir/default/

        echo -e -n "\nWhich service do you want to enable? (i.e. NetworkManager, \"q\" to break): "
        read -r service_enabler

        if [[ "$service_enabler" == "q" ]] ; then
          echo -e -n "\nAborting the operation...\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          break
        elif [[ ! -d /etc/sv/"$service_enabler" ]] ; then
          echo -e -n "\nService ${RED_LIGHT}$service_enabler${NORMAL} does not exist.\nPlease select another service to be enabled.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
        elif [[ -L /etc/runit/runsvdir/default/"$service_enabler" ]] ; then
          echo -e -n "\nService ${RED_LIGHT}$service_enabler${NORMAL} already enabled.\nPlease select another service to be enabled.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
        elif [[ "$service_enabler" == "" ]] ; then
          echo -e -n "\nPlease enter a valid service name.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          break
        else
          echo -e -n "\nEnabling service ${BLUE_LIGHT}$service_enabler${NORMAL}...\n\n"
          ln -s /etc/sv/"$service_enabler" /etc/runit/runsvdir/default/
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          break
        fi

      done
    
    elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
      echo -e -n "\n\nNo additional services were enabled.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
      break
    else
      echo -e -n "\nPlease answer y or n.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
    fi
  
  done

  while true ; do

    header_eds
    echo -e -n "\nDo you want to disable any service in your system? (y/n): "
    read -n 1 -r yn
  
    if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then

      while true ; do

        clear
        header_eds
        echo -e -n "\nListing all the services that could be disabled...\n"
        ls --almost-all --color=always /etc/runit/runsvdir/default/

        echo -e -n "\nWhich service do you want to disable? (i.e. NetworkManager, \"q\" to break): "
        read -r service_disabler

        if [[ "$service_disabler" == "q" ]] ; then
          echo -e -n "\nAborting the operation...\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          break
        elif [[ ! -L /etc/runit/runsvdir/default/"$service_disabler" ]] ; then
          echo -e -n "\nService ${RED_LIGHT}$service_disabler${NORMAL} does not exist.\nPlease select another service to be disabled.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
        elif [[ "$service_disabler" == "" ]] ; then
          echo -e -n "\nPlease enter a valid service name.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
        else
          echo -e -n "\nDisabling service ${BLUE_LIGHT}$service_disabler${NORMAL}...\n\n"
          rm -f /etc/runit/runsvdir/default/"$service_disabler"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          break
        fi

      done
    
    elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
      echo -e -n "\n\nNo additional services were disabled.\n\n"
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

    echo -e -n "\nDo you want to add any new user?\nOnly non-root users can later configure Void Packages (y/n): "
    read -n 1 -r yn
    
    if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
      
      while true ; do

        clear
        header_cu

        echo -e -n "\nPlease select a name for your new user (i.e. MyNewUser): "
        read -r newuser
      
        if [[ -z "$newuser" ]] ; then
          echo -e -n "\nPlease select a valid name.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
        
        elif [[ "$newuser" == "root" ]] ; then
          echo -e -n "\nYou can't add root again\nPlease select another name.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key

        elif getent passwd "$newuser" &> /dev/null ; then
          echo -e -n "\nUser ${BLUE_LIGHT}$newuser${NORMAL} already exists.\nPlease select another username.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          break
      
        else
          while true; do
          echo -e -n "\nIs username ${BLUE_LIGHT}$newuser${NORMAL} okay? (y/n and [ENTER]): "
          read -n 1 -r yn
        
          if [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
            echo -e -n "\nAborting, pleasae select another name.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key
            clear
            break
          elif [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
            echo -e -n "\nAdding new user ${BLUE_LIGHT}$newuser${NORMAL} and giving access to groups:\n"
            echo -e -n "kmem, wheel, tty, tape, daemon, floppy, disk, lp, dialout, audio, video,\nutmp, cdrom, optical, mail, storage, scanner, kvm, input, plugdev, users.\n"
            useradd --create-home --groups kmem,wheel,tty,tape,daemon,floppy,disk,lp,dialout,audio,video,utmp,cdrom,optical,mail,storage,scanner,kvm,input,plugdev,users "$newuser"
            
            echo -e -n "\nPlease select a new password for user ${BLUE_LIGHT}$newuser${NORMAL}:\n"
            while true ; do
              echo
              passwd "$newuser"
              if [[ "$?" == "0" ]] ; then
                break
              else
                echo -e -n "\n${RED_LIGHT}Something went wrong, please try again.${NORMAL}\n\n"
                read -n 1 -r -p "[Press any key to continue...]" key
                echo
              fi
            done

            while true ; do
              echo -e -n "\nListing all the available shells:\n\n"
              chsh --list-shells
              echo -e -n "\nWhich ${BLUE_LIGHT}shell${NORMAL} do you want to set for user ${BLUE_LIGHT}$newuser${NORMAL}?\nPlease enter the full path (i.e. /bin/sh): "
              read -r set_user_shell
              if [[ ! -x "$set_user_shell" ]] ; then
                echo -e -n "\nPlease enter a valid shell.\n\n"
                read -n 1 -r -p "[Press any key to continue...]" key
              else
                while true ; do
                  echo -e -n "\nYou entered: ${BLUE_LIGHT}$set_user_shell${NORMAL}.\n\n"
                  read -n 1 -r -p "Is this the desired shell? (y/n): " yn
                  if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
                    echo
                    echo
                    chsh --shell "$set_user_shell" "$newuser"
                    echo -e -n "\nDefault shell for user ${BLUE_LIGHT}$newuser${NORMAL} successfully changed.\n"
                    echo -e -n "\nUser ${BLUE_LIGHT}$newuser${NORMAL} successfully created.\n\n"
                    read -n 1 -r -p "[Press any key to continue...]" key
                    newuser_yn="y"
                    clear
                    break 4
                  elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
                    echo -e -n "\n\nPlease select another shell.\n\n"
                    read -n 1 -r -p "[Press any key to continue...]" key
                    break
                  else
                    echo -e -n "\nPlease answer y or n.\n\n"
                    read -n 1 -r -p "[Press any key to continue...]" key
                  fi
                done
              fi
            done

          else
            echo -e -n "\nPlease answer y or n.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key
          fi
          done
        fi
      done
      
    elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
      echo -e -n "\n\nNo additional user was added.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      if [[ "$newuser_yn" == "" ]] ; then
        newuser_yn="n"
      fi
      clear
      break
    
    else
      echo -e -n "\nPlease answer y or n.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
    fi
  
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

  if [[ "$newuser_yn" == "y" ]] ; then

    while true; do

      header_vp
  
      echo -e -n "\nDo you want to clone ${BLUE_LIGHT}Void Packages${NORMAL} repository to a specific folder for a specific non-root user? (y/n): "
      read -n 1 -r yn
    
      if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
      
        while true ; do

          clear
          header_vp

          echo -e -n "\nPlease enter an existing ${BLUE_LIGHT}username${NORMAL}: "
          read -r void_packages_username

          if [[ -z "$void_packages_username" ]] ; then
            echo -e -n "\nPlease input a valid username.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key

          elif [[ "$void_packages_username" == "root" ]] ; then
            echo -e -n "\nRoot user cannot be used to configure Void Packages.\nPlease select another username.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key

          elif ! getent passwd "$void_packages_username" &> /dev/null ; then
            echo -e -n "\nUser ${RED_LIGHT}$void_packages_username${NORMAL} doesn't exists.\nPlease select another username.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key

          else
            while true ; do
              clear
              header_vp
              echo -e -n "\nUser selected: ${BLUE_LIGHT}$void_packages_username${NORMAL}\n"
              echo -e -n "\nPlease enter a ${BLUE_LIGHT}full empty path${NORMAL} where you want to clone Void Packages.\nThe script will create that folder and then clone Void Packages into it (i.e. /opt/MyPath/ToVoidPackages/): "
              read -r void_packages_path
      
              if [[ -z "$void_packages_path" ]] ; then
                echo -e -n "\nPlease input a valid path.\n\n"
                read -n 1 -r -p "[Press any key to continue...]" key
                clear
      
              else
                while true; do
                  
                  if [[ ! -d "$void_packages_path" ]] ; then
                    if ! su - "$void_packages_username" --command "mkdir -p $void_packages_path 2> /dev/null" ; then
                      echo -e -n "\nUser ${RED_LIGHT}$void_packages_username${NORMAL} cannot create a folder in this directory.\nPlease select another path.\n\n"
                      read -n 1 -r -p "[Press any key to continue...]" key
                      break
                    fi
                  else
                    if [[ -n $(ls -A "$void_packages_path") ]] ; then
                      echo -e -n "\nDirectory ${RED_LIGHT}$void_packages_path${NORMAL} is not empty.\nPlease select another path.\n\n"
                      read -n 1 -r -p "[Press any key to continue...]" key
                      break
                    fi
                    if [[ $(stat --dereference --format="%U" $void_packages_path) != "$void_packages_username" ]] ; then
                      echo -e -n "\nUser ${RED_LIGHT}$void_packages_username${NORMAL} doesn't have write permission in this directory.\nPlease select another path.\n\n"
                      read -n 1 -r -p "[Press any key to continue...]" key
                      break
                    fi
                  fi
                  
                  echo -e -n "\nPath selected: ${BLUE_LIGHT}$void_packages_path${NORMAL}\n"
                  echo -e -n "\nIs this correct? (y/n): "
                  read -n 1 -r yn
        
                  if [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
                    echo -e -n "\nAborting, select another path.\n\n"
                    if [[ -z "$(ls -A $void_packages_path)" ]]; then
                      rm -rf "$void_packages_path"
                    fi
                    read -n 1 -r -p "[Press any key to continue...]" key
                    clear
                    break
                  elif [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
                    echo -e -n "\n\nSwitching to user ${BLUE_LIGHT}$void_packages_username${NORMAL}...\n\n"
su --login --shell=/bin/bash --whitelist-environment=void_packages_repo,void_packages_path "$void_packages_username" << EOSU
git clone "$void_packages_repo" "$void_packages_path"
echo -e -n "\nEnabling restricted packages...\n"
echo "XBPS_ALLOW_RESTRICTED=yes" >> "$void_packages_path"/etc/conf
EOSU
                    echo -e -n "\nLogging out user ${BLUE_LIGHT}$void_packages_username${NORMAL}...\n"
                    echo -e -n "\nVoid Packages successfully cloned and configured.\n\n"
                    read -n 1 -r -p "[Press any key to continue...]" key
                    clear
                    break 3
                  else
                    echo -e -n "\nPlease answer y or n.\n\n"
                    read -n 1 -r -p "[Press any key to continue...]" key
                  fi
                done
              fi
            done
          fi
        done
      
      elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
        echo -e -n "\n\nVoid Packages were not configured.\n\n"
        read -n 1 -r -p "[Press any key to continue...]" key
        clear
        break
    
      else
        echo -e -n "\nPlease answer y or n.\n\n"
        read -n 1 -r -p "[Press any key to continue...]" key
        clear
      fi
  
    done

  elif [[ "$newuser_yn" == "n" ]] ; then
    header_vp
    echo -e -n "\nNo non-root user was created.\nVoid Packages cannot be configured for root user.\n\n"
    read -n 1 -r -p "[Press any key to continue...]" key
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
    echo -e -n "\nSetting ${BLUE_LIGHT}$user_keyboard_layout${NORMAL} keyboard layout in /etc/rc.conf...\n"
    sed -i "/#KEYMAP=/s/.*/KEYMAP=\"$user_keyboard_layout\"/" /etc/rc.conf
    echo -e -n "\nSetting keymap in dracut configuration and regenerating initramfs...\n\n"
    echo -e "i18n_vars=\"/etc/rc.conf:KEYMAP\ni18n_install_all=\"no\"\"" >> /etc/dracut.conf.d/i18n.conf
    read -n 1 -r -p "[Press any key to continue...]" key
    echo
    dracut --regenerate-all --force --hostonly
    echo
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
        echo -e -n "\nKeyboard layout set to: ${BLUE_LIGHT}$user_keyboard_layout${NORMAL}.\n"
        echo -e -n "\nSetting keymap in dracut configuration and regenerating initramfs...\n\n"
        echo -e "i18n_vars=\"/etc/rc.conf:KEYMAP\ni18n_install_all=\"no\"\"" >> /etc/dracut.conf.d/i18n.conf
        read -n 1 -r -p "[Press any key to continue...]" key
        echo
        dracut --regenerate-all --force --hostonly
        echo
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

  echo -e -n "\n\nConfiguring AppArmor and setting it to enforce...\n"
  sed -i "/APPARMOR=/s/.*/APPARMOR=enforce/" /etc/default/apparmor
  sed -i "/#write-cache/s/^#//" /etc/apparmor/parser.conf
  sed -i "/#show_notifications/s/^#//" /etc/apparmor/notify.conf
  if [[ "$bootloader" == "EFISTUB" ]] || [[ "$bootloader" == "efistub" ]] ; then
    sed -i "/OPTIONS=/s/\"$/ apparmor=1 security=apparmor&/" /etc/default/efibootmgr-kernel-hook
    echo -e -n "\nReconfiguring kernel...\n\n"
    kernelver_pre=$(ls /lib/modules/)
    kernelver=$(echo ${kernelver_pre%.*})
    xbps-reconfigure -f linux"$kernelver"
  elif [[ "$bootloader" == "GRUB2" ]] || [[ "$bootloader" == "grub2" ]] ; then
    sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ apparmor=1 security=apparmor&/" /etc/default/grub
    echo -e -n "\nUpdating grub...\n\n"
    update-grub
  fi

  echo -e -n "\nReconfiguring every package...\n\n"
  read -n 1 -r -p "[Press any key to continue...]" key
  echo
  xbps-reconfigure -fa

  echo -e -n "\nEverything's done, exiting chroot...\n\n"

  read -n 1 -r -p "[Press any key to continue...]" key
  clear

}

initial_configuration
install_bootloader
create_swapfile
install_additional_packages
enable_disable_services
create_user
void_packages
finish_chroot
exit 0
EndOfScript

  if [[ ! -f "$HOME"/chroot.sh ]] ; then
    echo -e -n "Please run this script again to be sure that $HOME/chroot.sh script is created too."
    exit 1
  fi

  chmod +x "$HOME"/chroot.sh

}

function create_btrfs_map_physical_c {

  if [[ -f "$HOME"/btrfs_map_physical.c ]] ; then
    rm -f "$HOME"/btrfs_map_physical.c
  fi

cat >> "$HOME"/btrfs_map_physical.c << 'EndOfProgram'
// SPDX-FileCopyrightText: Omar Sandoval <osandov@osandov.com>
// SPDX-License-Identifier: MIT

#include <fcntl.h>
#include <getopt.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <linux/btrfs.h>
#include <linux/btrfs_tree.h>
#include <asm/byteorder.h>

#define le16_to_cpu __le16_to_cpu
#define le32_to_cpu __le32_to_cpu
#define le64_to_cpu __le64_to_cpu

static const char *progname = "btrfs_map_physical";

static void usage(bool error)
{
	fprintf(error ? stderr : stdout,
		"usage: %s [OPTION]... PATH\n"
		"\n"
		"Map the logical and physical extents of a file on Btrfs\n\n"
		"Pipe this to `column -ts $'\\t'` for prettier output.\n"
		"\n"
		"Btrfs represents a range of data in a file with a \"file extent\". Each\n"
		"file extent refers to a subset of an \"extent\". Each extent has a\n"
		"location in the logical address space of the filesystem belonging to a\n"
		"\"chunk\". Each chunk maps has a profile (i.e., RAID level) and maps to\n"
		"one or more physical locations, or \"stripes\", on disk. The extent may be\n"
		"\"encoded\" on disk (currently this means compressed, but in the future it\n"
		"may also be encrypted).\n"
		"\n"
		"An explanation of each printed field and its corresponding on-disk data\n"
		"structure is provided below:\n"
		"\n"
		"FILE OFFSET        Offset in the file where the file extent starts\n"
		"                   [(struct btrfs_key).offset]\n"
		"FILE SIZE          Size of the file extent\n"
		"                   [(struct btrfs_file_extent_item).num_bytes for most\n"
		"                   extents, (struct btrfs_file_extent_item).ram_bytes\n"
		"                   for inline extents]\n"
		"EXTENT OFFSET      Offset from the beginning of the unencoded extent\n"
		"                   where the file extent starts\n"
		"                   [(struct btrfs_file_extent_item).offset]\n"
		"EXTENT TYPE        Type of the extent (inline, preallocated, etc.)\n"
		"                   [(struct btrfs_file_extent_item).type];\n"
		"                   how it is encoded\n"
		"                   [(struct btrfs_file_extent_item){compression,\n"
		"                   encryption,other_encoding}];\n"
		"                   and its data profile\n"
		"                   [(struct btrfs_chunk).type]\n"
		"LOGICAL SIZE       Size of the unencoded extent\n"
		"                   [(struct btrfs_file_extent_item).ram_bytes]\n"
		"LOGICAL OFFSET     Location of the extent in the filesystem's logical\n"
		"                   address space\n"
		"                   [(struct btrfs_file_extent_offset).disk_bytenr]\n"
		"PHYSICAL SIZE      Size of the encoded extent on disk\n"
		"                   [(struct btrfs_file_extent_offset).disk_num_bytes]\n"
		"DEVID              ID of the device containing the extent\n"
		"                   [(struct btrfs_stripe).devid]\n"
		"PHYSICAL OFFSET    Location of the extent on the device\n"
		"                   [calculated from (struct btrfs_stripe).offset]\n"
		"\n"
		"FILE SIZE is rounded up to the sector size of the filesystem.\n"
		"\n"
		"Inline extents are stored with the metadata of the filesystem; this tool\n"
		"does not have the ability to determine their location.\n"
		"\n"
		"Gaps in a file are represented with a hole file extent unless the\n"
		"filesystem was formatted with the \"no-holes\" option.\n"
		"\n"
		"If the file extent was truncated, hole punched, cloned, or deduped,\n"
		"EXTENT OFFSET may be non-zero and LOGICAL SIZE may be different from\n"
		"FILE SIZE.\n"
		"\n"
		"Options:\n"
		"  -h, --help   display this help message and exit\n",
		progname);
	exit(error ? EXIT_FAILURE : EXIT_SUCCESS);
}

struct stripe {
	uint64_t devid;
	uint64_t offset;
};

struct chunk {
	uint64_t offset;
	uint64_t length;
	uint64_t stripe_len;
	uint64_t type;
	struct stripe *stripes;
	size_t num_stripes;
	size_t sub_stripes;
};

struct chunk_tree {
	struct chunk *chunks;
	size_t num_chunks;
};

static int read_chunk_tree(int fd, struct chunk **chunks, size_t *num_chunks)
{
	struct btrfs_ioctl_search_args search = {
		.key = {
			.tree_id = BTRFS_CHUNK_TREE_OBJECTID,
			.min_objectid = BTRFS_FIRST_CHUNK_TREE_OBJECTID,
			.min_type = BTRFS_CHUNK_ITEM_KEY,
			.min_offset = 0,
			.max_objectid = BTRFS_FIRST_CHUNK_TREE_OBJECTID,
			.max_type = BTRFS_CHUNK_ITEM_KEY,
			.max_offset = UINT64_MAX,
			.min_transid = 0,
			.max_transid = UINT64_MAX,
			.nr_items = 0,
		},
	};
	size_t items_pos = 0, buf_off = 0;
	size_t capacity = 0;
	int ret;

	*chunks = NULL;
	*num_chunks = 0;
	for (;;) {
		const struct btrfs_ioctl_search_header *header;
		const struct btrfs_chunk *item;
		struct chunk *chunk;
		size_t i;

		if (items_pos >= search.key.nr_items) {
			search.key.nr_items = 4096;
			ret = ioctl(fd, BTRFS_IOC_TREE_SEARCH, &search);
			if (ret == -1) {
				perror("BTRFS_IOC_TREE_SEARCH");
				return -1;
			}
			items_pos = 0;
			buf_off = 0;

			if (search.key.nr_items == 0)
				break;
		}

		header = (struct btrfs_ioctl_search_header *)(search.buf + buf_off);
		if (header->type != BTRFS_CHUNK_ITEM_KEY)
			goto next;

		item = (void *)(header + 1);
		if (*num_chunks >= capacity) {
			struct chunk *tmp;

			if (capacity == 0)
				capacity = 1;
			else
				capacity *= 2;
			tmp = realloc(*chunks, capacity * sizeof(**chunks));
			if (!tmp) {
				perror("realloc");
				return -1;
			}
			*chunks = tmp;
		}

		chunk = &(*chunks)[*num_chunks];
		chunk->offset = header->offset;
		chunk->length = le64_to_cpu(item->length);
		chunk->stripe_len = le64_to_cpu(item->stripe_len);
		chunk->type = le64_to_cpu(item->type);
		chunk->num_stripes = le16_to_cpu(item->num_stripes);
		chunk->sub_stripes = le16_to_cpu(item->sub_stripes);
		chunk->stripes = calloc(chunk->num_stripes,
					sizeof(*chunk->stripes));
		if (!chunk->stripes) {
			perror("calloc");
			return -1;
		}
		(*num_chunks)++;

		for (i = 0; i < chunk->num_stripes; i++) {
			const struct btrfs_stripe *stripe;

			stripe = &item->stripe + i;
			chunk->stripes[i].devid = le64_to_cpu(stripe->devid);
			chunk->stripes[i].offset = le64_to_cpu(stripe->offset);
		}

next:
		items_pos++;
		buf_off += sizeof(*header) + header->len;
		if (header->offset == UINT64_MAX)
			break;
		else
			search.key.min_offset = header->offset + 1;
	}
	return 0;
}

static struct chunk *find_chunk(struct chunk *chunks, size_t num_chunks,
				uint64_t logical)
{
	size_t lo, hi;

	if (!num_chunks)
		return NULL;

	lo = 0;
	hi = num_chunks - 1;
	while (lo <= hi) {
		size_t mid = lo + (hi - lo) / 2;

		if (logical < chunks[mid].offset)
			hi = mid - 1;
		else if (logical >= chunks[mid].offset + chunks[mid].length)
			lo = mid + 1;
		else
			return &chunks[mid];
	}
	return NULL;
}

static int print_extents(int fd, struct chunk *chunks, size_t num_chunks)
{
	struct btrfs_ioctl_search_args search = {
		.key = {
			.min_type = BTRFS_EXTENT_DATA_KEY,
			.max_type = BTRFS_EXTENT_DATA_KEY,
			.min_offset = 0,
			.max_offset = UINT64_MAX,
			.min_transid = 0,
			.max_transid = UINT64_MAX,
			.nr_items = 0,
		},
	};
	struct btrfs_ioctl_ino_lookup_args args = {
		.treeid = 0,
		.objectid = BTRFS_FIRST_FREE_OBJECTID,
	};
	size_t items_pos = 0, buf_off = 0;
	struct stat st;
	int ret;

	puts("FILE OFFSET\tFILE SIZE\tEXTENT OFFSET\tEXTENT TYPE\tLOGICAL SIZE\tLOGICAL OFFSET\tPHYSICAL SIZE\tDEVID\tPHYSICAL OFFSET");

	ret = fstat(fd, &st);
	if (ret == -1) {
		perror("fstat");
		return -1;
	}

	ret = ioctl(fd, BTRFS_IOC_INO_LOOKUP, &args);
	if (ret == -1) {
		perror("BTRFS_IOC_INO_LOOKUP");
		return -1;
	}

	search.key.tree_id = args.treeid;
	search.key.min_objectid = search.key.max_objectid = st.st_ino;
	for (;;) {
		const struct btrfs_ioctl_search_header *header;
		const struct btrfs_file_extent_item *item;
		uint8_t type;
		/* Initialize to silence GCC. */
		uint64_t file_offset = 0;
		uint64_t file_size = 0;
		uint64_t extent_offset = 0;
		uint64_t logical_size = 0;
		uint64_t logical_offset = 0;
		uint64_t physical_size = 0;
		struct chunk *chunk = NULL;

		if (items_pos >= search.key.nr_items) {
			search.key.nr_items = 4096;
			ret = ioctl(fd, BTRFS_IOC_TREE_SEARCH, &search);
			if (ret == -1) {
				perror("BTRFS_IOC_TREE_SEARCH");
				return -1;
			}
			items_pos = 0;
			buf_off = 0;

			if (search.key.nr_items == 0)
				break;
		}

		header = (struct btrfs_ioctl_search_header *)(search.buf + buf_off);
		if (header->type != BTRFS_EXTENT_DATA_KEY)
			goto next;

		item = (void *)(header + 1);

		type = item->type;
		file_offset = header->offset;
		if (type == BTRFS_FILE_EXTENT_INLINE) {
			file_size = logical_size = le64_to_cpu(item->ram_bytes);
			extent_offset = 0;
			physical_size = (header->len -
					 offsetof(struct btrfs_file_extent_item,
						  disk_bytenr));
		} else if (type == BTRFS_FILE_EXTENT_REG ||
			   type == BTRFS_FILE_EXTENT_PREALLOC) {
			file_size = le64_to_cpu(item->num_bytes);
			extent_offset = le64_to_cpu(item->offset);
			logical_size = le64_to_cpu(item->ram_bytes);
			logical_offset = le64_to_cpu(item->disk_bytenr);
			physical_size = le64_to_cpu(item->disk_num_bytes);
			if (logical_offset) {
				chunk = find_chunk(chunks, num_chunks,
						   logical_offset);
				if (!chunk) {
					printf("\n");
					fprintf(stderr,
						"could not find chunk containing %" PRIu64 "\n",
						logical_offset);
					return -1;
				}
			}
		}

		printf("%" PRIu64 "\t", file_offset);
		if (type == BTRFS_FILE_EXTENT_INLINE ||
		    type == BTRFS_FILE_EXTENT_REG ||
		    type == BTRFS_FILE_EXTENT_PREALLOC) {
			printf("%" PRIu64 "\t%" PRIu64 "\t", file_size,
			       extent_offset);
		} else {
			printf("\t\t");
		}

		switch (type) {
		case BTRFS_FILE_EXTENT_INLINE:
			printf("inline");
			break;
		case BTRFS_FILE_EXTENT_REG:
			if (logical_offset)
				printf("regular");
			else
				printf("hole");
			break;
		case BTRFS_FILE_EXTENT_PREALLOC:
			printf("prealloc");
			break;
		default:
			printf("type%u", type);
			break;
		}
		switch (item->compression) {
		case 0:
			break;
		case 1:
			printf(",compression=zlib");
			break;
		case 2:
			printf(",compression=lzo");
			break;
		case 3:
			printf(",compression=zstd");
			break;
		default:
			printf(",compression=%u", item->compression);
			break;
		}
		if (item->encryption)
			printf(",encryption=%u", item->encryption);
		if (item->other_encoding) {
			printf(",other_encoding=%u",
			       le16_to_cpu(item->other_encoding));
		}
		if (chunk) {
			switch (chunk->type & BTRFS_BLOCK_GROUP_PROFILE_MASK) {
			case 0:
				break;
			case BTRFS_BLOCK_GROUP_RAID0:
				printf(",raid0");
				break;
			case BTRFS_BLOCK_GROUP_RAID1:
				printf(",raid1");
				break;
			case BTRFS_BLOCK_GROUP_DUP:
				printf(",dup");
				break;
			case BTRFS_BLOCK_GROUP_RAID10:
				printf(",raid10");
				break;
			case BTRFS_BLOCK_GROUP_RAID5:
				printf(",raid5");
				break;
			case BTRFS_BLOCK_GROUP_RAID6:
				printf(",raid6");
				break;
			default:
				printf(",profile%" PRIu64,
				       (uint64_t)(chunk->type &
						  BTRFS_BLOCK_GROUP_PROFILE_MASK));
				break;
			}
		}
		printf("\t");

		if (type == BTRFS_FILE_EXTENT_INLINE ||
		    type == BTRFS_FILE_EXTENT_REG ||
		    type == BTRFS_FILE_EXTENT_PREALLOC)
			printf("%" PRIu64 "\t", logical_size);
		else
			printf("\t");

		if (type == BTRFS_FILE_EXTENT_REG ||
		    type == BTRFS_FILE_EXTENT_PREALLOC)
			printf("%" PRIu64 "\t", logical_offset);
		else
			printf("\t");

		if (type == BTRFS_FILE_EXTENT_INLINE ||
		    type == BTRFS_FILE_EXTENT_REG ||
		    type == BTRFS_FILE_EXTENT_PREALLOC)
			printf("%" PRIu64 "\t", physical_size);
		else
			printf("\t");

		if (chunk) {
			uint64_t offset, stripe_nr, stripe_offset;
			size_t stripe_index, num_stripes;
			size_t i;

			offset = logical_offset - chunk->offset;
			stripe_nr = offset / chunk->stripe_len;
			stripe_offset = offset - stripe_nr * chunk->stripe_len;
			switch (chunk->type & BTRFS_BLOCK_GROUP_PROFILE_MASK) {
			case 0:
			case BTRFS_BLOCK_GROUP_RAID0:
				stripe_index = stripe_nr % chunk->num_stripes;
				stripe_nr /= chunk->num_stripes;
				num_stripes = 1;
				break;
			case BTRFS_BLOCK_GROUP_RAID1:
			case BTRFS_BLOCK_GROUP_DUP:
				stripe_index = 0;
				num_stripes = chunk->num_stripes;
				break;
			case BTRFS_BLOCK_GROUP_RAID10: {
				size_t factor;

				factor = chunk->num_stripes / chunk->sub_stripes;
				stripe_index = (stripe_nr % factor *
						chunk->sub_stripes);
				stripe_nr /= factor;
				num_stripes = chunk->sub_stripes;
				break;
			}
			case BTRFS_BLOCK_GROUP_RAID5:
			case BTRFS_BLOCK_GROUP_RAID6: {
				size_t nr_parity_stripes, nr_data_stripes;

				if (chunk->type & BTRFS_BLOCK_GROUP_RAID6)
					nr_parity_stripes = 2;
				else
					nr_parity_stripes = 1;
				nr_data_stripes = (chunk->num_stripes -
						   nr_parity_stripes);
				stripe_index = stripe_nr % nr_data_stripes;
				stripe_nr /= nr_data_stripes;
				stripe_index = ((stripe_nr + stripe_index) %
						chunk->num_stripes);
				num_stripes = 1;
				break;
			}
			default:
				num_stripes = 0;
				break;
			}

			for (i = 0; i < num_stripes; i++) {
				if (i != 0)
					printf("\n\t\t\t\t\t\t\t");
				printf("%" PRIu64 "\t%" PRIu64,
				       chunk->stripes[stripe_index].devid,
				       chunk->stripes[stripe_index].offset +
				       stripe_nr * chunk->stripe_len +
				       stripe_offset);
				stripe_index++;
			}
		}
		printf("\n");

next:
		items_pos++;
		buf_off += sizeof(*header) + header->len;
		if (header->offset == UINT64_MAX)
			break;
		else
			search.key.min_offset = header->offset + 1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	struct option long_options[] = {
		{"help", no_argument, NULL, 'h'},
	};
	int fd, ret;
	struct chunk *chunks;
	size_t num_chunks, i;

	if (argv[0])
		progname = argv[0];

	for (;;) {
		int c;

		c = getopt_long(argc, argv, "h", long_options, NULL);
		if (c == -1)
			break;

		switch (c) {
		case 'h':
			usage(false);
		default:
			usage(true);
		}
	}
	if (optind != argc - 1)
		usage(true);

	fd = open(argv[optind], O_RDONLY);
	if (fd == -1) {
		perror("open");
		return EXIT_FAILURE;
	}

	ret = read_chunk_tree(fd, &chunks, &num_chunks);
	if (ret == -1)
		goto out;

	ret = print_extents(fd, chunks, num_chunks);
out:
	for (i = 0; i < num_chunks; i++)
		free(chunks[i].stripes);
	free(chunks);
	close(fd);
	return ret ? EXIT_FAILURE : EXIT_SUCCESS;
}
EndOfProgram

  if [[ ! -f "$HOME"/btrfs_map_physical.c ]] ; then
    echo -e -n "Please run this script again to be sure that $HOME/btrfs_map_physical.c is created too."
    exit 1
  fi

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
  
  while true ; do

    header_skl

    echo -e -n "\nIf you set your keyboard layout now, it will be also configured for your future system.\n"
    echo -e -n "\nIf you don't set it now, you can also do it later.\n"
    echo -e -n "\nDo you want to change your ${BLUE_LIGHT}keyboard layout${NORMAL}? (y/n): "
    read -n 1 -r yn
  
    if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then

      echo -e -n "\n\nPress any key to list all the keyboard layouts.\nMove with arrow keys and press \"q\" to exit the list."
      read -n 1 -r key
      echo
  
      find /usr/share/kbd/keymaps/ -type f -iname "*.map.gz" -printf "${BLUE_LIGHT_FIND}%f\0${NORMAL_FIND}\n" | sed -e 's/\..*$//' | sort |less --RAW-CONTROL-CHARS --no-init
  
      while true ; do
  
        echo -e -n "\nType the keyboard layout you want to set and press [ENTER] or just press [ENTER] to keep the one currently set: "
        read -r user_keyboard_layout
  
        if [[ -z "$user_keyboard_layout" ]] ; then
          echo -e -n "\nNo keyboard layout selected, keeping the previous one.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          break 2
        else
          if loadkeys "$user_keyboard_layout" 2> /dev/null ; then
            echo -e -n "\nKeyboad layout set to: ${BLUE_LIGHT}$user_keyboard_layout${NORMAL}.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key
            clear
            break 2
          else
            echo -e "\nNot a valid keyboard layout, please try again."
          fi
        fi
    
      done
    
    elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
      echo -e -n "\n\nKeeping the last selected keyboard layout.\n\n"
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

function header_cacti {
  
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}   ${GREEN_LIGHT}Setup internet connection${NORMAL}   ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function check_and_connect_to_internet {
  
  while true; do

    header_cacti

    echo -e -n "\nChecking internet connectivity...\n"

    if ! ping -c 2 8.8.8.8 &> /dev/null ; then
      echo -e -n "\nNo internet connection found.\n"
      echo -e -n "\nDo you want to connect to the ${BLUE_LIGHT}internet${NORMAL}? (y/n): "
      read -n 1 -r yn
    
      if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then

        while true ; do

          echo -e -n "\n\nDo you want to use wifi? (y/n): "
          read -n 1 -r yn
    
          if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
      
            if [[ -L /var/service/NetworkManager ]] ; then
        
              while true; do
                echo
                echo
                read -n 1 -r -p "Is your ESSID hidden? (y/n): " yn
            
                if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
                  echo
                  echo
                  nmcli device wifi
                  echo
                  nmcli --ask device wifi connect hidden yes
                  echo
                  read -n 1 -r -p "[Press any key to continue...]" key
                  clear
                  break 2
                elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
                  echo
                  echo
                  nmcli device wifi
                  echo
                  nmcli --ask device wifi connect
                  echo
                  read -n 1 -r -p "[Press any key to continue...]" key
                  clear
                  break 2
                else
                  echo -e -n "\nPlease answer y or n."
                fi
            
              done
          
            else
            
            ### UNTESTED ###
            
              while true; do
            
                echo
                echo
                ip a
                echo
          
                echo -e -n "Enter the wifi interface and press [ENTER]: "
                read -r wifi_interface
            
                if [[ -n "$wifi_interface" ]] ; then
            
                  echo -e -n "\nEnabling wpa_supplicant service...\n"
              
                  if [[ -L /var/service/wpa_supplicant ]] ; then
                    echo -e -n "\nService already enabled, restarting...\n"
                    sv restart {dhcpcd,wpa_supplicant}
                  else
                    echo -e -n "\nCreating service, starting...\n"
                    ln -s /etc/sv/wpa_supplicant /var/service/
                    sv restart dhcpcd
                    sleep 1
                    sv start wpa_supplicant
                  fi

                  echo -e -n "\nEnter your ESSID and press [ENTER]: "
                  read -r wifi_essid

                  if [[ ! -d /etc/wpa_supplicant/ ]] ; then
                    mkdir -p /etc/wpa_supplicant/
                  fi

                  echo -e -n "\nGenerating configuration files..."
                  wpa_passphrase "$wifi_essid" | tee /etc/wpa_supplicant/wpa_supplicant.conf
                  wpa_supplicant -B -c /etc/wpa_supplicant/wpa_supplicant.conf -i "$wifi_interface"
                  break 2
                else
                  echo -e -n "\nPlease input a valid wifi interface.\n"
                fi
              done
            fi

            if ping -c 2 8.8.8.8 &> /dev/null ; then
              echo -e -n "\nSuccessfully connected to the internet.\n\n"
              read -n 1 -r -p "[Press any key to continue...]" key
              clear
            fi
            break

          elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
            echo -e -n "\n\nPlease connect your ethernet cable and wait a minute before pressing any key."
            read -n 1 -r key
            clear
            break

          else
            echo -e -n "\nPlease answer y or n."
          fi

        done

      elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
        echo -e -n "\n\nNot connecting to the internet.\n\n"
        read -n 1 -r -p "[Press any key to continue...]" key
        clear
        break
      else
        echo -e -n "\nPlease answer y or n.\n\n"
        read -n 1 -r -p "[Press any key to continue...]" key
        clear
      fi

    else
      echo -e -n "\nAlready connected to the internet.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
      break
    fi

  done

}

function header_dw {
  
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}          ${GREEN_LIGHT}Disk wiping${NORMAL}          ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

}

function disk_wiping {
  
  while true; do

    header_dw
  
    echo -e -n "\nDo you want to ${BLUE_LIGHT}wipe${NORMAL} any drive? (y/n): "
    read -n 1 -r yn
    
    if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
      
      while true ; do

        clear
        header_dw

        echo -e -n "\nPrinting all the connected drives:\n\n"
        lsblk -p
    
        echo -e -n "\nWhich ${BLUE_LIGHT}drive${NORMAL} do you want to ${BLUE_LIGHT}wipe${NORMAL}?\nIt will be automatically selected as the drive to be partitioned.\n\nPlease enter the full drive path (i.e. /dev/sda): "
        read -r user_drive
      
        if [[ ! -b "$user_drive" ]] ; then
          echo -e -n "\nPlease select a valid drive.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
      
        else
          while true; do
          echo -e -n "\nDrive selected for wiping: ${BLUE_LIGHT}$user_drive${NORMAL}\n"
          echo -e -n "\n${RED_LIGHT}THIS DRIVE WILL BE WIPED, EVERY DATA INSIDE WILL BE LOST.${NORMAL}\n"
          echo -e -n "${RED_LIGHT}Are you sure you want to continue? (y/n and [ENTER]):${NORMAL} "
          read -r yn
        
          if [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
            echo -e -n "\nAborting, select another drive.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key
            clear
            break
          elif [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
            if grep -q "$user_drive" /proc/mounts ; then
              echo -e -n "\nDrive already mounted.\nChanging directory to $HOME and unmounting every partition before wiping...\n"
              cd "$HOME"
              umount --recursive "$(findmnt $user_drive | awk -F " " 'FNR == 2 {print $1}')"
              echo -e -n "\nDrive unmounted successfully.\n"
            fi

            echo -e -n "\nWiping the drive...\n\n"
            wipefs -a "$user_drive"
            sync
            echo -e -n "\nDrive successfully wiped.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key
            clear
            break 3
          else
            echo -e -n "\nPlease answer y or n.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key
          fi
          done
        fi
      done
      
    elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
      echo -e -n "\n\nNo additional changes were made.\n\n"
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

function header_dp {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}       ${GREEN_LIGHT}Disk partitioning${NORMAL}       ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  
}

function disk_partitioning {
  
  while true; do

    header_dp
    
    if [[ -z "$user_drive" ]] ; then
      echo -e -n "\nNo drive previously selected for partitioning.\n"
      echo -e -n "\nDo you want to ${BLUE_LIGHT}partition${NORMAL} any drive? (y/n): "
      read -n 1 -r yn
    else
      while true ; do
        echo -e -n "\nDrive previously selected for partitioning: ${BLUE_LIGHT}$user_drive${NORMAL}.\n\n"
        read -n 1 -r -p "Do you want to change it? (y/n): " yn
        if [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
          echo -e -n "\n\nKeeping the previously selected drive.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          yn="y"
          break
        elif [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
          echo -e -n "\n\nPlease select another drive.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          user_drive=''
          yn="y"
          break
        else
          echo -e -n "\nPlease answer y or n.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
        fi
      done
    fi
    
    if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
      
      while true ; do
    
        if [[ -n "$user_drive" ]] ; then

          if grep -q "$user_drive" /proc/mounts ; then
            echo -e -n "\nDrive already mounted.\nChanging directory to $HOME and unmounting every partition before partitioning...\n"
            cd "$HOME"
            umount --recursive "$(findmnt $user_drive | awk -F " " 'FNR == 2 {print $1}')"
            echo -e -n "\nDrive unmounted successfully.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key
            clear
          fi
      
          while true ; do

            clear
            header_dp
          
            echo -e -n "\nSuggested disk layout:"
            echo -e -n "\n- GPT as disk label type for UEFI systems;"
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
                echo -e -n "\nPlease select only one of the three suggested tools.\n\n"
                read -n 1 -r -p "[Press any key to continue...]" key
                ;;
            esac
            
          done
          
          while true; do

            clear
            header_dp

            echo
            lsblk -p "$user_drive"
            echo
            read -n 1 -r -p "Is this the desired partition table? (y/n): " yn
          
            if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
              echo -e -n "\n\nDrive partitioned, keeping changes.\n\n"
              read -n 1 -r -p "[Press any key to continue...]" key
              clear
              break 3
            elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
              echo -e -n "\n\nPlease partition your drive again.\n\n"
              read -n 1 -r -p "[Press any key to continue...]" key
              break
            else
              echo -e -n "\nPlease answer y or n.\n\n"
              read -n 1 -r -p "[Press any key to continue...]" key
              clear
            fi
          done
          
        else
      
          while true ; do
        
            clear
            header_dp

            echo -e -n "\nPrinting all the connected drive(s):\n\n"
            
            lsblk -p
          
            echo -e -n "\nWhich drive do you want to partition?\nPlease enter the full drive path (i.e. /dev/sda): "
            read -r user_drive
    
            if [[ ! -b "$user_drive" ]] ; then
              echo -e -n "\nPlease select a valid drive.\n\n"
              read -n 1 -r -p "[Press any key to continue...]" key
      
            else
          
              while true; do
              echo -e -n "\nYou selected: $user_drive.\n"
              echo -e -n "\n${RED_LIGHT}THIS DRIVE WILL BE PARTITIONED, EVERY DATA INSIDE WILL BE LOST.${NORMAL}\n"
              echo -e -n "${RED_LIGHT}Are you sure you want to continue? (y/n and [ENTER]):${NORMAL} "
              read -r yn
          
              if [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
                echo -e -n "\nAborting, select another drive.\n\n"
                read -n 1 -r -p "[Press any key to continue...]" key
                break
              elif [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
                if grep -q "$user_drive" /proc/mounts ; then
                  echo -e -n "\nDrive already mounted.\nChanging directory to $HOME and unmounting every partition before selecting it for partitioning...\n"
                  cd "$HOME"
                  umount --recursive "$(findmnt $user_drive | awk -F " " 'FNR == 2 {print $1}')"
                  echo -e -n "\nDrive unmounted successfully.\n\n"
                  read -n 1 -r -p "[Press any key to continue...]" key
                fi

                echo -e -n "\nCorrect drive selected, back to tool selection...\n\n"
                read -n 1 -r -p "[Press any key to continue...]" key
                break 2
              else
                echo -e -n "\nPlease answer y or n.\n\n"
                read -n 1 -r -p "[Press any key to continue...]" key
              fi
              done
            
            fi
          
          done
        
        fi
      
      done
    
    elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
      echo -e -n "\n\nNo additional changes were made.\n\n"
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

function header_de {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}        ${GREEN_LIGHT}Disk encryption${NORMAL}        ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  
}

function disk_encryption {

  while true ; do

    header_de

    echo -e -n "\nDo you want to enable ${BLUE_LIGHT}Full Disk Encryption${NORMAL}? (y/n): "
    read -n 1 -r encryption_yn

    if [[ "$encryption_yn" == "y" ]] || [[ "$encryption_yn" == "Y" ]] ; then

      clear
      header_de
      echo -e -n "\nPrinting all the connected drives:\n\n"
      lsblk -p
    
      echo -e -n "\nWhich ${BLUE_LIGHT}/ [root]${NORMAL} partition do you want to ${BLUE_LIGHT}encrypt${NORMAL}?\nPlease enter the full partition path (i.e. /dev/sda1): "
      read -r encrypted_partition
      
      if [[ ! -b "$encrypted_partition" ]] ; then
      echo -e -n "\nPlease select a valid partition.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
      
      else
        while true; do
          echo -e -n "\nYou selected: ${BLUE_LIGHT}$encrypted_partition${NORMAL}.\n"
          echo -e -n "\n${RED_LIGHT}THIS DRIVE WILL BE FORMATTED AND ENCRYPTED, EVERY DATA INSIDE WILL BE LOST.${NORMAL}\n"
          echo -e -n "${RED_LIGHT}Are you sure you want to continue? (y/n and [ENTER]):${NORMAL} "
          read -r yn
        
          if [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
            echo -e -n "\nAborting, select another partition.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key
            clear
            break
          elif [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
            echo -e -n "\nCorrect partition selected.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key
            clear

            header_de
            echo -e -n "\nThe selected partition will now be encrypted with LUKS version 1 or 2.\n"
            echo -e -n "\n${RED_LIGHT}LUKS version 1${NORMAL}\n"
            echo -e -n "- Can be used by both EFISTUB and GRUB2\n"
            echo -e -n "\n${RED_LIGHT}LUKS version 2${NORMAL}\n"
            echo -e -n "- Can be used only by EFISTUB and it will automatically be selected later.\n"
            echo -e -n "  [GRUB2 LUKS version 2 support with encrypted /boot is still limited: https://savannah.gnu.org/bugs/?55093].\n"

            while true ; do
              echo -e -n "\nWhich LUKS version do you want to use? (1/2 and [ENTER]): "
              read -r luks_ot
              if [[ "$luks_ot" == "1" ]] || [[ "$luks_ot" == "2" ]] ; then
                echo -e -n "\nUsing LUKS version ${BLUE_LIGHT}$luks_ot${NORMAL}.\n\n"
                while true ; do
                  echo
                  cryptsetup luksFormat --type=luks"$luks_ot" "$encrypted_partition"
                  if [[ "$?" == "0" ]] ; then
                    break
                  else
                    echo -e -n "\n${RED_LIGHT}Something went wrong, please try again.${NORMAL}\n\n"
                    read -n 1 -r -p "[Press any key to continue...]" key
                    echo
                  fi
                done
                echo -e -n "\nPartition successfully encrypted.\n\n"
                read -n 1 -r -p "[Press any key to continue...]" key
                clear
                break
              else
                echo -e -n "\nPlease enter 1 or 2.\n\n"
                read -n 1 -r -p "[Press any key to continue...]" key
              fi
            done

            while true ; do
              header_de
              echo -e -n "\nEnter a ${BLUE_LIGHT}name${NORMAL} for the ${BLUE_LIGHT}encrypted partition${NORMAL} without any spaces (i.e. MyEncryptedLinuxPartition).\n"
              echo -e -n "\nThe name will be used to mount the encrypted partition to ${BLUE_LIGHT}/dev/mapper/[...]${NORMAL} : "
              read -r encrypted_name
              if [[ -z "$encrypted_name" ]] ; then
                echo -e -n "\nPlease enter a valid name.\n\n"
                read -n 1 -r -p "[Press any key to continue...]" key
                clear
              else
                while true ; do
                  echo -e -n "\nYou entered: ${BLUE_LIGHT}$encrypted_name${NORMAL}.\n\n"
                  read -n 1 -r -p "Is this the desired name? (y/n): " yn

                  if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
                    echo -e -n "\n\nPartition will now be mounted as: ${BLUE_LIGHT}/dev/mapper/$encrypted_name${NORMAL}\n"
                    while true ; do
                      echo
                      cryptsetup open "$encrypted_partition" "$encrypted_name"
                      if [[ "$?" == "0" ]] ; then
                        break
                      else
                        echo -e -n "\n${RED_LIGHT}Something went wrong, please try again.${NORMAL}\n\n"
                        read -n 1 -r -p "[Press any key to continue...]" key
                        echo
                      fi
                    done
                    echo -e -n "\nEncrypted partition successfully mounted.\n\n"
                    read -n 1 -r -p "[Press any key to continue...]" key
                    final_drive=/dev/mapper/"$encrypted_name"
                    clear
                    break 2
                  elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
                    echo -e -n "\n\nPlease select another name.\n\n"
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

            break 2
          else
            echo -e -n "\nPlease answer y or n.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key
          fi
        done

      fi

    elif [[ "$encryption_yn" == "n" ]] || [[ "$encryption_yn" == "N" ]] ; then

      echo -e -n "\nEncryption won't be enabled.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear

      while true ; do
        header_de
        echo -e -n "\nPrinting all the connected drives:\n\n"
        lsblk -p

        echo -e -n "\nWhich partition will be the ${BLUE_LIGHT}unecrypted / [root]${NORMAL} partition?\nPlease enter the full partition path (i.e. /dev/sda1): "
        read -r root_partition

        if [[ ! -b "$root_partition" ]] ; then
          echo -e -n "\nPlease select a valid partition.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
        else
          while true; do
            echo -e -n "\nYou selected: ${BLUE_LIGHT}$root_partition${NORMAL}.\n"
            echo -e -n "\n${RED_LIGHT}THIS PARTITION WILL BE FORMATTED, EVERY DATA INSIDE WILL BE LOST.${NORMAL}\n"
            echo -e -n "${RED_LIGHT}Are you sure you want to continue? (y/n and [ENTER]):${NORMAL} "
            read -r yn
          
            if [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
              echo -e -n "\nAborting, select another partition.\n\n"
              read -n 1 -r -p "[Press any key to continue...]" key
              clear
              break
            elif [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
              if grep -q "$root_partition" /proc/mounts ; then
                echo -e -n "\nPartition already mounted.\nChanging directory to $HOME and unmounting it before formatting...\n"
                cd "$HOME"
                umount --recursive "$(findmnt $root_partition | awk -F " " 'FNR == 2 {print $1}')"
                echo -e -n "\nDrive unmounted successfully.\n\n"
                read -n 1 -r -p "[Press any key to continue...]" key
              fi
              final_drive="$root_partition"
              echo -e -n "\nCorrect partition selected.\n\n"
              read -n 1 -r -p "[Press any key to continue...]" key
              clear
              break 3
            else
              echo -e -n "\nPlease answer y or n.\n\n"
              read -n 1 -r -p "[Press any key to continue...]" key
            fi
          done
        fi
      done

    else
      echo -e -n "\nPlease answer y or n.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear

    fi

  done
 
}

function header_lc {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}   ${GREEN_LIGHT}Logical Volume Management${NORMAL}   ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  
}

function lvm_creation {

  while true; do

    header_lc

    echo -e -n "\nWith LVM will be easier in the future to add more space\nto the root partition without formatting the whole system\n"
    echo -e -n "\nDo you want to use ${BLUE_LIGHT}LVM${NORMAL}? (y/n): "
    read -n 1 -r lvm_yn

    if [[ "$lvm_yn" == "y" ]] || [[ "$lvm_yn" == "Y" ]] ; then

      clear

      while true ; do

        header_lc

        echo -e -n "\nCreating logical partitions wih LVM.\n"

        echo -e -n "\nEnter a ${BLUE_LIGHT}name${NORMAL} for the ${BLUE_LIGHT}Volume Group${NORMAL} without any spaces (i.e. MyLinuxVolumeGroup).\n"
        echo -e -n "\nThe name will be used to mount the Volume Group as: ${BLUE_LIGHT}/dev/mapper/[...]${NORMAL} : "
        read -r vg_name
    
        if [[ -z "$vg_name" ]] ; then
          echo -e -n "\nPlease enter a valid name.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
        else
          while true ; do
            echo -e -n "\nYou entered: ${BLUE_LIGHT}$vg_name${NORMAL}.\n\n"
            read -n 1 -r -p "Is this the desired name? (y/n): " yn
        
            if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
              echo -e -n "\n\nVolume Group will now be created and mounted as: ${BLUE_LIGHT}/dev/mapper/$vg_name${NORMAL}\n\n"
              vgcreate "$vg_name" "$final_drive"
              echo
              read -n 1 -r -p "[Press any key to continue...]" key
              clear
              break 2
            elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
              echo -e -n "\n\nPlease select another name.\n\n"
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

        header_lc

        echo -e -n "\nEnter a ${BLUE_LIGHT}name${NORMAL} for the ${BLUE_LIGHT}Logical Volume${NORMAL} without any spaces (i.e. MyLinuxLogicVolume).\nIts size will be the entire partition previosly selected.\n"
        echo -e -n "\nThe name will be used to mount the Logical Volume as: ${BLUE_LIGHT}/dev/mapper/$vg_name-[...]${NORMAL} : "
        read -r lv_root_name
    
        if [[ -z "$lv_root_name" ]] ; then
          echo -e -n "\nPlease enter a valid name.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
        else
          while true ; do
            echo -e -n "\nYou entered: ${BLUE_LIGHT}$lv_root_name${NORMAL}.\n\n"
            read -n 1 -r -p "Is this correct? (y/n): " yn
          
            if [[ "$yn" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
              echo -e -n "\n\nLogical Volume ${BLUE_LIGHT}$lv_root_name${NORMAL} will now be created.\n\n"
              lvcreate --name "$lv_root_name" -l +100%FREE "$vg_name"
              echo
              read -n 1 -r -p "[Press any key to continue...]" key
              final_drive=/dev/mapper/"$vg_name"-"$lv_root_name"
              clear
              break 3
            elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
              echo -e -n "\n\nPlease select another name.\n\n"
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

    elif [[ "$lvm_yn" == "n" ]] || [[ "$lvm_yn" == "N" ]] ; then
      echo -e -n "\n\nLVM won't be used.\n\n"
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

function header_cf {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}      ${GREEN_LIGHT}Filesystem creation${NORMAL}      ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  
}

function create_filesystems {

  while true ; do

    header_cf

    echo -e -n "\nFormatting partitions with proper filesystems.\n\nEFI partition will be formatted as ${BLUE_LIGHT}FAT32${NORMAL}.\nRoot partition will be formatted as ${BLUE_LIGHT}BTRFS${NORMAL}.\n"

    echo
    lsblk -p
    echo

    echo -e -n "\nWhich partition will be the ${BLUE_LIGHT}bootable EFI${NORMAL} partition?\n"
    read -r -p "Please enter the full partition path (i.e. /dev/sda1): " boot_partition

    if [[ "$boot_partition" == "$encrypted_partition" ]] || [[ "$boot_partition" == "$root_partition" ]] ; then
      echo -e -n "\nPlease select a partition different from your root partition.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
    elif [[ ! -b "$boot_partition" ]] ; then
      echo -e -n "\nPlease select a valid partition.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
    else
      while true; do
        echo -e -n "\nYou selected: ${BLUE_LIGHT}$boot_partition${NORMAL}.\n"
        echo -e -n "\n${RED_LIGHT}THIS PARTITION WILL BE FORMATTED, EVERY DATA INSIDE WILL BE LOST.${NORMAL}\n"
        echo -e -n "${RED_LIGHT}Are you sure you want to continue? (y/n and [ENTER]):${NORMAL} "
        read -r yn
          
        if [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
          echo -e -n "\nAborting, select another partition.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          break
        elif [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
          if grep -q "$boot_partition" /proc/mounts ; then
            echo -e -n "\nPartition already mounted.\nChanging directory to $HOME and unmounting it before formatting...\n"
            cd "$HOME"
            umount --recursive "$(findmnt $boot_partition | awk -F " " 'FNR == 2 {print $1}')"
            echo -e -n "\nDrive unmounted successfully.\n\n"
            read -n 1 -r -p "[Press any key to continue...]" key
          fi

          echo -e -n "\nCorrect partition selected.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          
          while true ; do

            header_cf

            echo -e -n "\nEnter a ${BLUE_LIGHT}label${NORMAL} for the ${BLUE_LIGHT}boot${NORMAL} partition without any spaces (i.e. MYBOOTPARTITION): "
            read -r boot_name
    
            if [[ -z "$boot_name" ]] ; then
              echo -e -n "\nPlease enter a valid name.\n\n"
              read -n 1 -r -p "[Press any key to continue...]" key
              clear
            else
              while true ; do
                echo -e -n "\nYou entered: ${BLUE_LIGHT}$boot_name${NORMAL}.\n\n"
                read -n 1 -r -p "Is this the desired name? (y/n): " yn
          
                if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
                  echo -e -n "\n\nBoot partition ${BLUE_LIGHT}$boot_partition${NORMAL} will now be formatted as ${BLUE_LIGHT}FAT32${NORMAL} with ${BLUE_LIGHT}$boot_name${NORMAL} label.\n\n"
                  mkfs.vfat -n "$boot_name" -F 32 "$boot_partition"
                  sync
                  echo -e -n "\nPartition successfully formatted.\n\n"
                  read -n 1 -r -p "[Press any key to continue...]" key
                  clear
                  break 4
                elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
                  echo -e -n "\n\nPlease select another name.\n\n"
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

        else
          echo -e -n "\nPlease answer y or n.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
        fi
      done

    fi

  done

  while true ; do

    header_cf

    echo -e -n "\nEnter a ${BLUE_LIGHT}label${NORMAL} for the ${BLUE_LIGHT}root${NORMAL} partition without any spaces (i.e. MyRootPartition): "
    read -r root_name
    
    if [[ -z "$root_name" ]] ; then
      echo -e -n "\nPlease enter a valid name.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
    else
      while true ; do

        echo -e -n "\nYou entered: ${BLUE_LIGHT}$root_name${NORMAL}.\n\n"
        read -n 1 -r -p "Is this the desired name? (y/n): " yn
          
        if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
          echo -e -n "\n\n${BLUE_LIGHT}Root${NORMAL} partition ${BLUE_LIGHT}$final_drive${NORMAL} will now be formatted as ${BLUE_LIGHT}BTRFS${NORMAL} with ${BLUE_LIGHT}$root_name${NORMAL} label.\n\n"
          mkfs.btrfs --force -L "$root_name" "$final_drive"
          sync
          echo -e -n "\nPartition successfully formatted.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          break 2
        elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
          echo -e -n "\n\nPlease select another name.\n\n"
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

}

function header_cbs {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}        ${GREEN_LIGHT}BTRFS subvolume${NORMAL}        ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  
}

function create_btrfs_subvolumes {
  
  header_cbs

  if [[ -n $(lsblk "$final_drive" --discard | awk -F " " 'FNR == 2 {print $3}') ]] && [[ -n $(lsblk "$final_drive" --discard | awk -F " " 'FNR == 2 {print $4}') ]] ; then
    hdd_ssd=ssd
  else
    hdd_ssd=hdd
  fi

  echo -e -n "\nBTRFS subvolumes will now be created with default options.\n\n"
  echo -e -n "Default options:\n"
  echo -e -n "- rw\n"
  echo -e -n "- noatime\n"
  if [[ "$hdd_ssd" == "ssd" ]] ; then
    echo -e -n "- discard=async\n"
  fi
  echo -e -n "- compress-force=zstd\n"
  echo -e -n "- space_cache=v2\n"
  echo -e -n "- commit=120\n"

  echo -e -n "\nSubvolumes that will be created:\n"
  echo -e -n "- /@\n"
  echo -e -n "- /@home\n"
  echo -e -n "- /@snapshots\n"
  echo -e -n "- /var/cache/xbps\n"
  echo -e -n "- /var/tmp\n"
  echo -e -n "- /var/log\n"

  echo -e -n "\n${BLUE_LIGHT}If you prefer to change any option, please quit this script NOW and modify it according to you tastes.${NORMAL}\n\n"
  read -n 1 -r -p "Press any key to continue or Ctrl+C to quit now..." key

  echo -e -n "\n\nThe root partition ${BLUE_LIGHT}$final_drive${NORMAL} will now be mounted to /mnt.\n"

  if grep -q /mnt /proc/mounts ; then
    echo -e -n "Everything mounted to /mnt will now be unmounted...\n"
    cd "$HOME"
    umount --recursive /mnt
    echo -e -n "\nDone.\n\n"
    read -n 1 -r -p "[Press any key to continue...]" key
  fi

  echo -e -n "\nCreating BTRFS subvolumes and mounting them to /mnt...\n"

  if [[ "$hdd_ssd" == "ssd" ]] ; then
    export BTRFS_OPT=rw,noatime,discard=async,compress-force=zstd,space_cache=v2,commit=120
  elif [[ "$hdd_ssd" == "hdd" ]] ; then
    export BTRFS_OPT=rw,noatime,compress-force=zstd,space_cache=v2,commit=120
  fi
  mount -o "$BTRFS_OPT" "$final_drive" /mnt
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@home
  btrfs subvolume create /mnt/@snapshots
  umount /mnt
  mount -o "$BTRFS_OPT",subvol=@ "$final_drive" /mnt
  mkdir /mnt/home
  mount -o "$BTRFS_OPT",subvol=@home "$final_drive" /mnt/home/
  mkdir -p /mnt/var/cache
  btrfs subvolume create /mnt/var/cache/xbps
  btrfs subvolume create /mnt/var/tmp
  btrfs subvolume create /mnt/var/log

  echo -e -n "\nDone.\n\n"
  read -n 1 -r -p "[Press any key to continue...]" key
  clear

}

function header_ibsac {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}   ${GREEN_LIGHT}Base system installation${NORMAL}    ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  
}

function install_base_system_and_chroot {

  header_ibsac

  while true ; do
  
    echo -e -n "\nSelect which ${BLUE_LIGHT}architecture${NORMAL} do you want to use:\n\n"
    
    select user_arch in x86_64 x86_64-musl ; do
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
          echo -e -n "\nPlease select one of the two architectures.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          ;;
      esac
    done

  done

  echo -e -n "\nCopying RSA keys...\n"
  mkdir -p /mnt/var/db/xbps/keys
  cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/

  echo -e -n "\nInstalling base system...\n\n"
  read -n 1 -r -p "[Press any key to continue...]" key
  echo
  XBPS_ARCH="$ARCH" xbps-install -Suvy xbps
  XBPS_ARCH="$ARCH" xbps-install -Suvy -r /mnt -R "$REPO" base-system btrfs-progs cryptsetup grub-x86_64-efi efibootmgr lvm2 grub-btrfs grub-btrfs-runit NetworkManager bash-completion nano gcc apparmor git curl util-linux tar coreutils binutils xtools fzf plocate ictree void-repo-multilib void-repo-nonfree void-repo-multilib-nonfree
  XBPS_ARCH="$ARCH" xbps-install -Suvy -r /mnt -R "$REPO"
  if grep -m 1 "model name" /proc/cpuinfo | grep --ignore-case "intel" &> /dev/null ; then
    XBPS_ARCH="$ARCH" xbps-install -Suvy -r /mnt -R "$REPO" intel-ucode
  fi
  
  echo -e -n "\nMounting folders for chroot...\n"
  for dir in sys dev proc ; do
    mount --rbind /$dir /mnt/$dir
    mount --make-rslave /mnt/$dir
  done
  mount --rbind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars/
  
  echo -e -n "\nCopying /etc/resolv.conf...\n"
  cp -L /etc/resolv.conf /mnt/etc/

  if [[ ! -L /var/services/NetworkManager ]] ; then
    echo -e -n "\nCopying /etc/wpa_supplicant/wpa_supplicant.conf...\n"
    cp -L /etc/wpa_supplicant/wpa_supplicant.conf /mnt/etc/wpa_supplicant/
  else
    echo -e -n "\nCopying /etc/NetworkManager/system-connections/...\n"
    cp -L /etc/NetworkManager/system-connections/* /mnt/etc/NetworkManager/system-connections/
  fi
  
  echo -e -n "\nChrooting...\n\n"
  read -n 1 -r -p "[Press any key to continue...]" key
  cp "$HOME"/chroot.sh /mnt/root/
  cp "$HOME"/btrfs_map_physical.c /mnt/root/

  BTRFS_OPT="$BTRFS_OPT" boot_partition="$boot_partition" encryption_yn="$encryption_yn" luks_ot="$luks_ot" encrypted_partition="$encrypted_partition" encrypted_name="$encrypted_name" lvm_yn="$lvm_yn" vg_name="$vg_name" lv_root_name="$lv_root_name" user_drive="$user_drive" final_drive="$final_drive" user_keyboard_layout="$user_keyboard_layout" hdd_ssd="$hdd_ssd" void_packages_repo="$void_packages_repo" ARCH="$ARCH" BLUE_LIGHT="$BLUE_LIGHT" BLUE_LIGHT_FIND="$BLUE_LIGHT_FIND" GREEN_DARK="$GREEN_DARK" GREEN_LIGHT="$GREEN_LIGHT" NORMAL="$NORMAL" NORMAL_FIND="$NORMAL_FIND" RED_LIGHT="$RED_LIGHT" PS1='(chroot) # ' chroot /mnt/ /bin/bash "$HOME"/chroot.sh

  header_ibsac
  
  echo -e -n "\nCleaning...\n"
  rm -f /mnt/root/chroot.sh
  rm -f /mnt/root/btrfs_map_physical.c
  rm -f /mnt/root/btrfs_map_physical

  echo -e -n "\nUnmounting partitions...\n\n"
  if findmnt /mnt &> /dev/null ; then
    umount --recursive /mnt
  fi
  
  if [[ "$lvm_yn" == "y" ]] || [[ "$lvm_yn" == "Y" ]] ; then
    lvchange -an /dev/mapper/"$vg_name"-"$lv_root_name"
    vgchange -an /dev/mapper/"$vg_name"
  fi

  if [[ "$encryption_yn" == "y" ]] || [[ "$encryption_yn" == "Y" ]] ; then
    cryptsetup close /dev/mapper/"$encrypted_name"
  fi

  echo
  read -n 1 -r -p "[Press any key to continue...]" key
  clear

}

function outro {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}    ${GREEN_LIGHT}Installation completed${NORMAL}     ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

  echo -e -n "\nAfter rebooting into the new installed system, be sure to:\n"
  echo -e -n "- If you plan yo use snapper, after installing it and creating a configuration for / [root],\n  uncomment the line relative to /.snapshots folder\n"
  echo -e -n "\n${BLUE_LIGHT}Everything's done, goodbye.${NORMAL}\n\n"

  read -n 1 -r -p "[Press any key to exit...]" key
  clear

}

# Main

check_if_bash
check_if_run_as_root
check_if_uefi
create_chroot_script
create_btrfs_map_physical_c
intro
set_keyboard_layout
check_and_connect_to_internet
disk_wiping
disk_partitioning
disk_encryption
lvm_creation
create_filesystems
create_btrfs_subvolumes
install_base_system_and_chroot
outro
exit 0
