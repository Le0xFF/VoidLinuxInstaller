#! /bin/bash

# Author: Le0xFF
# Script name: VoidLinuxInstaller.sh
# Github repo: https://github.com/Le0xFF/VoidLinuxInstaller
#
# Description: My first attempt at creating a bash script, trying to converting my gist into a bash script. Bugs are more than expected.
#              https://gist.github.com/Le0xFF/ff0e3670c06def675bb6920fe8dd64a3
#
# Version: 1.0.0

# Variables

user_drive=''
encrypted_partition=''
encrypted_name=''
vg_name=''
lv_root_name=''
lv_root_size=''
lv_home_name=''
boot_partition=''

# Colours

BLUE_LIGHT="\e[1;34m"
GREEN_DARK="\e[0;32m"
GREEN_LIGHT="\e[1;32m"
NORMAL="\e[0m"
RED_LIGHT="\e[1;31m"

# Functions

function check_if_bash {

  if [[ "$(ps -p $$ | tail -1 | awk '{print $NF}')" != "bash" ]] ; then
    echo -e -n "Please run this script with bash shell: \"bash VoidLinuxInstaller.sh\".\n"
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

cat << EOD >> "$HOME"/chroot.sh
#! /bin/bash

function set_root {

  clear
  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}# VLI #\${NORMAL}            \${GREEN_LIGHT}Chroot\${NORMAL}             \${GREEN_DARK}#\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######\${NORMAL}     \${GREEN_LIGHT}Setting root password\${NORMAL}     \${GREEN_DARK}#\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  
  echo -e -n "\nSetting root password:\n\n"
  passwd root
  
  echo -e -n "\nSetting root permissions...\n\n"
  chown root:root /
  chmod 755 /

  read -n 1 -r -p "[Press any key to continue...]" key
  clear
    
}

function edit_fstab {

  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}# VLI #\${NORMAL}            \${GREEN_LIGHT}Chroot\${NORMAL}             \${GREEN_DARK}#\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######\${NORMAL}        \${GREEN_LIGHT}fstab creation\${NORMAL}         \${GREEN_DARK}#\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"

  echo -e -n "\nExporting variables that will be used for fstab...\n"
  export UEFI_UUID=\$(blkid -s UUID -o value "\$boot_partition")
  export LUKS_UUID=\$(blkid -s UUID -o value "\$encrypted_partition")
  export ROOT_UUID=\$(blkid -s UUID -o value /dev/mapper/"\$vg_name"-"\$lv_root_name")
  export HOME_UUID=\$(blkid -s UUID -o value /dev/mapper/"\$vg_name"-"\$lv_home_name")
  
  echo -e -n "\nWriting fstab...\n\n"
  sed -i '/tmpfs/d' /etc/fstab
cat << EOF >> /etc/fstab

# root partition
UUID=\$ROOT_UUID / btrfs \$BTRFS_OPT,subvol=@ 0 1

# home partition
UUID=\$HOME_UUID /home btrfs \$BTRFS_OPT,subvol=@home 0 2

# root snapshots
UUID=\$ROOT_UUID /.snapshots btrfs \$BTRFS_OPT,subvol=@snapshots 0 2

# EFI partition
UUID=\$UEFI_UUID /boot/efi vfat defaults,noatime 0 2

# TMPfs
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
EOF

  read -n 1 -r -p "[Press any key to continue...]" key
  clear

}

function generate_random_key {

  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}# VLI #\${NORMAL}            \${GREEN_LIGHT}Chroot\${NORMAL}             \${GREEN_DARK}#\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######\${NORMAL}     \${GREEN_LIGHT}Random key generation\${NORMAL}     \${GREEN_DARK}#\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"

  echo -e -n "\nGenerate random key to avoid typing password twice at boot...\n\n"
  dd bs=512 count=4 if=/dev/random of=/boot/volume.key
  
  echo -e -n "\nRandom key generated, unlocking the encrypted partition...\n"
  cryptsetup luksAddKey "\$encrypted_partition" /boot/volume.key
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

  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}# VLI #\${NORMAL}            \${GREEN_LIGHT}Chroot\${NORMAL}             \${GREEN_DARK}#\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######\${NORMAL}     \${GREEN_LIGHT}Dracut configuration\${NORMAL}      \${GREEN_DARK}#\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"

  echo -e -n "\nAdding random key to dracut configuration...\n"
cat << EOF >> /etc/dracut.conf.d/10-crypt.conf
install_items+=" /boot/volume.key /etc/crypttab "
EOF

  echo -e -n "\nAdding other needed dracut configuration files...\n"
  echo -e "hostonly=yes\nhostonly_cmdline=yes" >> /etc/dracut.conf.d/00-hostonly.conf
  echo -e "add_dracutmodules+=\" crypt btrfs lvm resume \"" >> /etc/dracut.conf.d/20-addmodules.conf
  echo -e "tmpdir=/tmp" >> /etc/dracut.conf.d/30-tmpfs.conf

  echo -e -n "\nGenerating new dracut initramfs...\n\n"
  dracut --force --hostonly --kver \$(ls /usr/lib/modules/)

  echo
  read -n 1 -r -p "[Press any key to continue...]" key
  clear

}

function header_ig {

  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}# VLI #\${NORMAL}            \${GREEN_LIGHT}Chroot\${NORMAL}             \${GREEN_DARK}#\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######\${NORMAL}       \${GREEN_LIGHT}GRUB installation\${NORMAL}       \${GREEN_DARK}#\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  
}

function install_grub {

  header_ig

  echo -e -n "\nEnabling CRYPTODISK in GRUB...\n"
cat << EOF >> /etc/default/grub

GRUB_ENABLE_CRYPTODISK=y
EOF

  sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ rd.auto=1 rd.luks.name=\$LUKS_UUID=\$encrypted_name rd.luks.allow-discards=\$LUKS_UUID&/" /etc/default/grub

  if ! grep -q efivar /proc/mounts ; then
    echo -e -n "\nMounting efivarfs...\n"
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars/
  fi

  echo -e -n "\nInstalling GRUB on \${BLUE_LIGHT}/boot/efi\${NORMAL} partition with \${BLUE_LIGHT}VoidLinux\${NORMAL} as bootloader-id...\n\n"
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=VoidLinux --boot-directory=/boot --recheck

  echo -e -n "\nEnabling SSD trim...\n\n"
  sed -i 's/issue_discards = 0/issue_discards = 1/' /etc/lvm/lvm.conf

  read -n 1 -r -p "[Press any key to continue...]" key
  clear

}

function finish_chroot {

  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}# VLI #\${NORMAL}            \${GREEN_LIGHT}Chroot\${NORMAL}             \${GREEN_DARK}#\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######\${NORMAL}       \${GREEN_LIGHT}Enabling services\${NORMAL}       \${GREEN_DARK}#\${NORMAL}\n"
  echo -e -n "\${GREEN_DARK}#######################################\${NORMAL}\n"

  echo -e -n "\nEnabling internet service at first boot...\n"
  ln -s /etc/sv/dbus /etc/runit/runsvdir/default/
  ln -s /etc/sv/NetworkManager /etc/runit/runsvdir/default/

  echo -e -n "\nReconfiguring every package...\n\n"
  read -n 1 -r -p "[Press any key to continue...]" key
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
EOD

  if [[ ! -f "$HOME"/chroot.sh ]] ; then
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
  echo -e -n "${GREEN_DARK}{    {${NORMAL}   ${GREEN_LIGHT}ppppppQ   p    Q${NORMAL}       This script will install Void Linux, with LVM, BTRFS, with separated /home partition,\n"
  echo -e -n " ${GREEN_DARK}{    {${NORMAL}            ${GREEN_LIGHT}ppppQ${NORMAL}        with Full Disk Encryption using LUKS1/2 and it will enable trim on SSD. So please don't use this script on old HDD.\n"
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
  
    echo -e -n "\nDo you want to change your keyboard layout? (y/n): "
    read -n 1 -r yn
  
    if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then

      echo -e -n "\n\nPress any key to list all the keyboard layouts.\nMove with arrow keys and press \"q\" to exit the list."
      read -n 1 -r key
      echo
  
      ls --color=always -R /usr/share/kbd/keymaps/ | grep "\.map.gz" | sed -e 's/\..*$//' | less --RAW-CONTROL-CHARS --no-init
  
      while true ; do
  
        echo
        read -r -p "Type the keyboard layout you want to set and press [ENTER] or just press [ENTER] to keep the one currently set: " user_keyboard_layout
  
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
      echo -e -n "\nNo internet connection found.\n\n"
      read -n 1 -r -p "Do you want to connect to the internet? (y/n): " yn
    
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
  
    echo
    read -n 1 -r -p "Do you want to wipe any drive? (y/n): " yn
    
    if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
      
      while true ; do

        clear
        header_dw

        echo -e -n "\nPrinting all the connected drives:\n\n"
        lsblk -p
    
        echo -e -n "\nWhich drive do you want to wipe?\nIt will be automatically selected as the drive to be partitioned.\n\nPlease enter the full drive path (i.e. /dev/sda): "
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
              umount -l "$user_drive"?*
              echo -e -n "\nDrive unmounted successfully.\n"
            fi

            echo -e -n "\nWiping the drive...\n"
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
      echo -e -n "\nNo drive previously selected for partitioning.\n\n"
      read -n 1 -r -p "Do you want to partition any drive? (y/n): " yn
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
            umount -l "$user_drive"?*
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
            echo -e -n "\n\nThose two will be physical partition.\nYou don't need to create a /home partition now because it will be created later as a logical one.\n"
          
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
              echo -e -n "\nYou selected "$user_drive".\n"
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
                  umount -l "$user_drive"?*
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

          echo -e -n "\nThe selected partition will now be encrypted with LUKS.\n"
          echo -e -n "\nKeep in mind that GRUB LUKS version 2 support is still limited (https://savannah.gnu.org/bugs/?55093).\n${RED_LIGHT}Choosing it could result in an unbootable system so it's strongly recommended to use LUKS version 1.${NORMAL}\n"

          while true ; do
            echo -e -n "\nWhich LUKS version do you want to use? (1/2 and [ENTER]): "
            read ot
            if [[ "$ot" == "1" ]] || [[ "$ot" == "2" ]] ; then
              echo -e -n "\nUsing LUKS version ${BLUE_LIGHT}$ot${NORMAL}.\n\n"
              cryptsetup luksFormat --type=luks"$ot" "$encrypted_partition"
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

            echo -e -n "\nEnter a ${BLUE_LIGHT}name${NORMAL} for the ${BLUE_LIGHT}encrypted partition${NORMAL} without any spaces (i.e. MyEncryptedLinuxPartition): "
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
                  echo -e -n "\n\nPartition will now be mounted as: ${BLUE_LIGHT}/dev/mapper/$encrypted_name${NORMAL}\n\n"
                  cryptsetup open "$encrypted_partition" "$encrypted_name"
                  echo -e -n "\nEncrypted partition successfully mounted.\n\n"
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
                  clear
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
    
  done
 
}

function header_lc {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}   ${GREEN_LIGHT}Logical Volume Management${NORMAL}   ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  
}

function lvm_creation {

  while true ; do

    header_lc

    echo -e -n "\nCreating logical partitions wih LVM.\n"

    echo -e -n "\nEnter a ${BLUE_LIGHT}name${NORMAL} for the ${BLUE_LIGHT}Volume Group${NORMAL} without any spaces (i.e. MyLinuxVolumeGroup): "
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
          vgcreate "$vg_name" /dev/mapper/"$encrypted_name"
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

    echo -e -n "\nEnter a ${BLUE_LIGHT}name${NORMAL} for the ${BLUE_LIGHT}Logical root Volume${NORMAL} without any spaces and its size.\nBe sure to make no errors (i.e. MyLogicLinuxRootPartition 100G): "
    read -r lv_root_name lv_root_size
    
    if [[ -z "$lv_root_name" ]] || [[ -z "$lv_root_size" ]] ; then
      echo -e -n "\nPlease enter valid values.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
    else
      while true ; do
        echo -e -n "\nYou entered: ${BLUE_LIGHT}$lv_root_name${NORMAL} and ${BLUE_LIGHT}$lv_root_size${NORMAL}.\n\n"
        read -n 1 -r -p "Are these correct? (y/n): " yn
          
        if [[ "$yn" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
          echo -e -n "\n\nLogical Volume ${BLUE_LIGHT}$lv_root_name${NORMAL} of size ${BLUE_LIGHT}$lv_root_size${NORMAL} will now be created.\n\n"
          lvcreate --name "$lv_root_name" -L "$lv_root_size" "$vg_name"
          echo
          read -n 1 -r -p "[Press any key to continue...]" key
          clear
          break 2
        elif [[ "$yn" == "n" ]] || [[ "$yn" == "N" ]] ; then
          echo -e -n "\n\nPlease select other values.\n\n"
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

    echo -e -n "\nEnter a ${BLUE_LIGHT}name${NORMAL} for the ${BLUE_LIGHT}Logical home Volume${NORMAL} without any spaces.\nIts size will be the remaining free space (i.e. MyLogicLinuxHomePartition): "
    read -r lv_home_name
    
    if [[ -z "$lv_home_name" ]] ; then
      echo -e -n "\nPlease enter a valid name.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear      
    else
      while true ; do
        echo -e -n "\nYou entered: ${BLUE_LIGHT}$lv_home_name${NORMAL}.\n\n"
        read -n 1 -r -p "Is this the desired name? (y/n): " yn
          
        if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
          echo -e -n "\n\nLogical Volume ${BLUE_LIGHT}$lv_home_name${NORMAL} will now be created.\n\n"
          lvcreate --name "$lv_home_name" -l +100%FREE "$vg_name"
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

}

function header_cf {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}      ${GREEN_LIGHT}Filesystem creation${NORMAL}      ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  
}

function create_filesystems {

  while true ; do

    header_cf

    echo -e -n "\nFormatting partitions with proper filesystems.\n\nEFI partition will be formatted as ${BLUE_LIGHT}FAT32${NORMAL}.\nRoot and home partition will be formatted as ${BLUE_LIGHT}BTRFS${NORMAL}.\n"

    echo
    lsblk -p
    echo

    echo -e -n "\nWhich partition will be the ${BLUE_LIGHT}/boot/efi${NORMAL} partition?\n"
    read -r -p "Please enter the full partition path (i.e. /dev/sda1): " boot_partition
    
    if [[ ! -b "$boot_partition" ]] ; then
      echo -e -n "\nPlease select a valid drive.\n\n"
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
            umount -l "$boot_partition"
            echo -e -n "\nDrive unmounted successfully.\n"
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
          echo -e -n "\n\n${BLUE_LIGHT}Root${NORMAL} partition ${BLUE_LIGHT}/dev/mapper/$vg_name-$lv_root_name${NORMAL} will now be formatted as ${BLUE_LIGHT}BTRFS${NORMAL} with ${BLUE_LIGHT}$root_name${NORMAL} label.\n\n"
          mkfs.btrfs -L "$root_name" /dev/mapper/"$vg_name"-"$lv_root_name"
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

  while true ; do

    header_cf

    echo -e -n "\nEnter a ${BLUE_LIGHT}label${NORMAL} for the ${BLUE_LIGHT}home${NORMAL} partition without any spaces (i.e. MyHomePartition): "
    read -r home_name
    
    if [[ -z "$home_name" ]] ; then
      echo -e -n "\nPlease enter a valid name.\n\n"
      read -n 1 -r -p "[Press any key to continue...]" key
      clear
    else
      while true ; do
        echo -e -n "\nYou entered: ${BLUE_LIGHT}$home_name${NORMAL}.\n\n"
        read -n 1 -r -p "Is this the desired name? (y/n): " yn
          
        if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]] ; then
          echo -e -n "\n\n${BLUE_LIGHT}Home${NORMAL} partition ${BLUE_LIGHT}/dev/mapper/$vg_name-$lv_home_name${NORMAL} will now be formatted as ${BLUE_LIGHT}BTRFS${NORMAL} with ${BLUE_LIGHT}$home_name${NORMAL} label.\n\n"
          mkfs.btrfs -L "$home_name" /dev/mapper/"$vg_name"-"$lv_home_name"
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

  echo -e -n "\nBTRFS subvolumes will now be created with default options.\n\n"
  echo -e -n "Default options:\n"
  echo -e -n "- rw\n"
  echo -e -n "- noatime\n"
  echo -e -n "- ssd\n"
  echo -e -n "- compress=zstd\n"
  echo -e -n "- space_cache=v2\n"
  echo -e -n "- commit=120\n"

  echo -e -n "\nSubvolumes that will be created:\n"
  echo -e -n "- /@\n"
  echo -e -n "- /@snapshots\n"
  echo -e -n "- /home/@home\n"
  echo -e -n "- /var/cache/xbps\n"
  echo -e -n "- /var/tmp\n"
  echo -e -n "- /var/log\n"

  echo -e -n "\n${BLUE_LIGHT}If you prefer to change any option, please quit this script NOW and modify it according to you tastes.${NORMAL}\n\n"
  read -n 1 -r -p "Press any key to continue or Ctrl+C to quit now..." key

  echo -e -n "\n\nThe root partition you selected (/dev/mapper/$vg_name-$lv_root_name) will now be mounted to /mnt.\n"
  if grep -q /mnt /proc/mounts ; then
    echo -e -n "Everything mounted to /mnt will now be unmounted...\n"
    cd "$HOME"
    umount -l /mnt
    echo -e -n "\nDone.\n\n"
    read -n 1 -r -p "[Press any key to continue...]" key
  fi

  echo -e -n "\nCreating BTRFS subvolumes and mounting them to /mnt...\n"

  export BTRFS_OPT=rw,noatime,ssd,compress=zstd,space_cache=v2,commit=120
  mount -o "$BTRFS_OPT" /dev/mapper/"$vg_name"-"$lv_root_name" /mnt
  mkdir /mnt/home
  mount -o "$BTRFS_OPT" /dev/mapper/"$vg_name"-"$lv_home_name" /mnt/home
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@snapshots
  btrfs subvolume create /mnt/home/@home
  umount /mnt/home
  umount /mnt
  mount -o "$BTRFS_OPT",subvol=@ /dev/mapper/"$vg_name"-"$lv_root_name" /mnt
  mkdir /mnt/home
  mkdir /mnt/.snapshots
  mount -o "$BTRFS_OPT",subvol=@home /dev/mapper/"$vg_name"-"$lv_home_name" /mnt/home/
  mount -o "$BTRFS_OPT",subvol=@snapshots /dev/mapper/"$vg_name"-"$lv_root_name" /mnt/.snapshots/
  mkdir -p /mnt/boot/efi
  mount -o rw,noatime "$boot_partition" /mnt/boot/efi/
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
          echo -e -n "\n${BLUE_LIGHT}$user_arch${NORMAL} selected.\n\n"
          ARCH="$user_arch"
          export REPO=https://repo-default.voidlinux.org/current
          read -n 1 -r -p "[Press any key to continue...]" key
          break 2
          ;;
        x86_64-musl)
          echo -e -n "\n${BLUE_LIGHT}$user_arch${NORMAL} selected.\n\n"
          ARCH="$user_arch"
          export REPO=https://repo-default.voidlinux.org/current/musl
          read -n 1 -r -p "[Press any key to continue...]" key
          break 2
          ;;
        *)
          echo -e -n "\nPlease select one of the two architectures.\n\n"
          read -n 1 -r -p "[Press any key to continue...]" key
          ;;
      esac
    done

  done

  echo -e -n "\nInstalling base system...\n\n"
  XBPS_ARCH="$ARCH" xbps-install -Suy xbps
  XBPS_ARCH="$ARCH" xbps-install -Sy -r /mnt -R "$REPO" base-system btrfs-progs cryptsetup grub-x86_64-efi lvm2 grub-btrfs grub-btrfs-runit NetworkManager bash-completion nano
  
  echo -e -n "\nMounting folders for chroot...\n"
  for dir in sys dev proc ; do
    mount --rbind /$dir /mnt/$dir
    mount --make-rslave /mnt/$dir
  done
  
  echo -e -n "\nCopying /etc/resolv.conf...\n"
  cp -L /etc/resolv.conf /mnt/etc/

  if [[ ! -L /var/services/NetworkManager ]] ; then
    echo -e -n "\nCopying /etc/wpa_supplicant/wpa_supplicant.conf...\n"
    cp -L /etc/wpa_supplicant/wpa_supplicant.conf /mnt/etc/wpa_supplicant/
  fi
  
  echo -e -n "\nChrooting...\n\n"
  read -n 1 -r -p "[Press any key to continue...]" key
  cp "$HOME"/chroot.sh /mnt/root/
  BTRFS_OPT="$BTRFS_OPT" boot_partition="$boot_partition" encrypted_partition="$encrypted_partition" encrypted_name="$encrypted_name" vg_name="$vg_name" lv_root_name="$lv_root_name" lv_home_name="$lv_home_name" user_drive="$user_drive" BLUE_LIGHT="$BLUE_LIGHT" GREEN_DARK="$GREEN_DARK" GREEN_LIGHT="$GREEN_LIGHT" NORMAL="$NORMAL" RED_LIGHT="$RED_LIGHT" PS1='(chroot) # ' chroot /mnt/ /bin/bash "$HOME"/chroot.sh

  header_ibsac
  
  echo -e -n "\nCleaning...\n"
  rm -f /mnt/home/root/chroot.sh

  echo -e -n "\nUnmounting partitions...\n\n"
  umount /dev/mapper/"$vg_name"-"$lv_home_name"
  umount /dev/mapper/"$vg_name"-"$lv_root_name"
  umount -l /dev/mapper/"$vg_name"-"$lv_root_name"
  lvchange -an /dev/mapper/"$vg_name"-"$lv_home_name"
  lvchange -an /dev/mapper/"$vg_name"-"$lv_root_name"
  cryptsetup close /dev/mapper/"$encrypted_name"

  read -n 1 -r -p "[Press any key to continue...]" key
  clear

}

function outro {

  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"
  echo -e -n "${GREEN_DARK}# VLI #${NORMAL}    ${GREEN_LIGHT}Installation completed${NORMAL}     ${GREEN_DARK}#${NORMAL}\n"
  echo -e -n "${GREEN_DARK}#######################################${NORMAL}\n"

  echo -e -n "\nAfter rebooting into the new installed system, be sure to:\n"
  echo -e -n "- Change your default shell\n"
  echo -e -n "- Change your hostname in /etc/hostname\n"
  echo -e -n "- Modify /etc/rc.conf according to the official documentation\n"
  echo -e -n "- Uncomment the right line in /etc/default/libc-locales\n"
  echo -e -n "- Add the same uncommented line in /etc/locale.conf\n"
  echo -e -n "- Run \"xbps-reconfigure -fa\"\n"
  echo -e -n "- Reboot\n"
  echo -e -n "\nEverything's done, goodbye.\n\n"

  read -n 1 -r -p "[Press any key to exit...]" key
  clear

}

# Main

check_if_bash
check_if_run_as_root
check_if_uefi
create_chroot_script
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
