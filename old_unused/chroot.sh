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
    else
      header_ib
      echo -e -n "\nSelect which ${BLUE_LIGHT}bootloader${NORMAL} do you want to use (EFISTUB, GRUB2): "
      read -r bootloader
    fi

    if [[ "$bootloader" == "EFISTUB" ]] || [[ "$bootloader" == "efistub" ]] ; then
      echo -e -n "\n\nMounting $boot_partition to /boot...\n"
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
                echo -e -n "\nGenerating random key to avoid typing password twice at boot...\n\n"
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
  echo -e -n "\n\nWriting EFI partition to /etc/fstab...\n"
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
