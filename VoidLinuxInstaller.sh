#! /bin/bash

# Variables

user_drive=''
encrypted_partition=''
encrypted_name=''
vg_name=''
lv_root_name=''
lv_root_size=''
lv_home_name=''

# Functions

function check_if_bash () {

  if [[ "$(ps -p $$ | tail -1 | awk '{print $NF}')" != "bash" ]] ; then
    echo "Please run this script with bash shell: \"bash VoidLinuxInstaller.sh\"."
    exit 1
  fi

}

function check_if_run_as_root () {

  if [[ "${UID}" != "0" ]]; then
    echo "Please run this script as root."
    exit 1
  fi

}

function set_keyboard_layout () {
  
  while true; do
  
    echo
    read -n 1 -r -p "Do you want to change your keyboard layout? (y/n): " yn
  
    if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then

      echo -e -n "\n\nPress any key to list all the keyboard layouts.\nMove with arrow keys and press \"q\" to exit the list."
      read -n 1 key
      echo
  
      ls --color=always -R /usr/share/kbd/keymaps/ | grep "\.map.gz" | sed -e 's/\..*$//' | less --RAW-CONTROL-CHARS --no-init
  
      while true ; do
  
        echo
        read -p "Choose the keyboard layout you want to set and press [ENTER] or just press [ENTER] to keep the one currently set: " user_keyboard_layout
  
        if [[ -z "${user_keyboard_layout}" ]] ; then
          echo -e "\nNo keyboard layout selected, keeping the previous one."
          break
        else
      
          if loadkeys ${user_keyboard_layout} 2> /dev/null ; then
            echo -e "\nKeyboad layout set to \"${user_keyboard_layout}\"."
            break
          else
            echo -e "\nNot a valid keyboard layout, please try again."
          fi
        fi
    
      done
    
    elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
      echo -e "\n\nKeeping the last selected keyboard layout."
      break
    
    else
      echo -e "\nPlease answer y or n."
    fi
  
  done
  
}

function check_and_connect_to_internet () {
  
  while true; do

    echo -e "\nChecking internet connectivity..."

    if ! ping -c2 8.8.8.8 &> /dev/null ; then
      echo -e -n "\nNo internet connection found.\n\n"
      read -n 1 -r -p "Do you want to connect to the internet? (y/n): " yn
    
      if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
    
        echo -e -n "\n\nDo you want to use wifi? (y/n): "
        read -n 1 yn
    
        if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
      
          if [[ -e /var/service/NetworkManager ]] ; then
        
            while true; do
              echo
              echo
              read -n 1 -r -p "Is your ESSID hidden? (y/n): " yn
            
              if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
                echo
                echo
                nmcli device wifi
                echo
                nmcli --ask device wifi connect hidden yes
                break
              elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
                echo
                echo
                nmcli device wifi
                echo
                nmcli --ask device wifi connect
                break
              else
                echo -e -n "\n\nPlease answer y or n."
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
              read wifi_interface
            
              if [[ ! -z "${wifi_interface}" ]] ; then
            
                echo -e "\nEnabling wpa_supplicant service..."
              
                if [[ -e /var/service/wpa_supplicant ]] ; then
                  echo -e "\nService already enabled, restarting..."
                  sv restart {dhcpcd,wpa_supplicant}
                else
                  echo -e "\nCreating service, starting..."
                  ln -s /etc/sv/wpa_supplicant /var/service/
                  sv restart dhcpcd
                  sleep 1
                  sv start wpa_supplicant
                fi
            
                echo -e -n "\nEnter your ESSID and press [ENTER]: "
                read wifi_essid
              
                if [[ -d /etc/wpa_supplicant/ ]] ; then
                  continue
                else
                  mkdir -p /etc/wpa_supplicant/
                fi
              
                echo -e "\nGenerating configuration files..."
                wpa_passphrase "${wifi_essid}" | tee /etc/wpa_supplicant/wpa_supplicant.conf
                wpa_supplicant -B -c /etc/wpa_supplicant/wpa_supplicant.conf -i "${wifi_interface}"
              
                break
              
              else
                echo -e "\nPlease input a valid wifi interface."
              fi
            
            done
          
          fi
      
          if ping -c2 8.8.8.8 &> /dev/null ; then
            echo -e "\nSuccessfully connected to the internet."
          fi
        
          break
        
        elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
          echo -e -n "\n\nPlease connect your ethernet cable and wait a minute before pressing any key."
          read -n 1 -r wait
      
        else
          echo -e "\nPlease answer y or n."
        fi
    
      elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
        echo
        break
      
      else
        echo -e -n "\n\nPlease answer y or n.\n"
      fi

    else
      echo -e "\nAlready connected to the internet."
      break
    fi

  done

}

function disk_wiping () {
  
  while true; do
  
    echo
    read -n 1 -r -p "Do you want to wipe any drive? (y/n): " yn
    echo
    
    if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
      
      out="0"
      
      while [ ${out} -eq "0" ] ; do
      
        echo -e "\nPrinting all the connected drives:\n"
        lsblk -p
    
        echo
        read -r -p "Which drive do you want to wipe? Please enter the full drive path (i.e. /dev/sda): " user_drive
      
        if [[ ! -e "${user_drive}" ]] ; then
          echo -e "\nPlease select a valid drive."
      
        else
          while true; do
          echo -e "\nDrive selected for wiping: ${user_drive}"
          echo -e "\nTHIS DRIVE WILL BE WIPED, EVERY DATA INSIDE WILL BE LOST."
          read -r -p "Are you sure you want to continue? (y/n and [ENTER]): " yn
        
          if [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
            echo -e "\nAborting, select another drive."
            break
          elif [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
            if cat /proc/mounts | grep "${user_drive}" &> /dev/null ; then
              echo -e -n "\nDrive already mounted.\nChanging directory to "${HOME}" and unmounting every partition before wiping...\n"
              cd $HOME
              umount -l "${user_drive}"?*
              echo -e -n "\nDrive unmounted successfully.\n"
            fi

            echo -e -n "\nWiping the drive...\n"
            wipefs -a "${user_drive}"
            echo -e -n "\nDrive successfully wiped.\n"
            out="1"
            break
          else
            echo -e "\nPlease answer y or n."
          fi
          done
        fi
      done
      
    elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
      echo -e "\nNo additional changes were made."
      break
    
    else
      echo -e "\n\nPlease answer y or n."
    fi
  
  done
}

function disk_partitioning () {
  
  while true; do
    
    echo
    read -n 1 -r -p "Do you want to partition any drive? (y/n): " yn
    echo
    
    if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
      
      out1="0"
      
      while [ "${out1}" -eq "0" ] ; do
    
        if [[ ! -z "${user_drive}" ]] ; then

          if cat /proc/mounts | grep "${user_drive}" &> /dev/null ; then
            echo -e -n "\nDrive already mounted.\nChanging directory to "${HOME}" and unmounting every partition before partitioning...\n"
            cd $HOME
            umount -l "${user_drive}"?*
            echo -e -n "\nDrive unmounted successfully.\n"
          fi
        
          out="0"
      
          while [ "${out}" -eq "0" ] ; do
          
            echo -e -n "\nSuggested disk layout:"
            echo -e -n "\n- GPT as disk label type for UEFI systems;"
            echo -e -n "\n- Less than 1 GB for /boot/efi as first partition [EFI System];"
            echo -e -n "\n- Rest of the disk for / as second partition [Linux filesystem]."
            echo -e -n "\n\nThose two will be physical partition.\nYou don't need to create a /home partition now because it will be created later as a logical one.\n"
          
            echo -e -n "\nDrive selected for partitioning: ${user_drive}\n\n"
          
            read -r -p "Which tool do you want to use? (fdisk/cfdisk/sfdisk): " tool
      
            case "${tool}" in
              fdisk)
                fdisk "${user_drive}"
                break
                ;;
              cfdisk)
                cfdisk "${user_drive}"
                break
                ;;
              sfdisk)
                sfdisk "${user_drive}"
                break
                ;;
              *)
                echo -e -n "\nPlease select only one of the three suggested tools.\n"
                ;;
            esac
            
          done
          
          while true; do
            echo
            lsblk -p "${user_drive}"
            echo
            read -n 1 -r -p "Is this the desired partition table? (y/n): " yn
          
            if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
              echo -e -n "\n\nDrive partitioned, keeping changes.\n"
              out="1"
              out1="1"
              break
            elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
              echo -e -n "\n\nPlease partition your drive again.\n"
              break
            else
              echo -e "\n\nPlease answer y or n."
            fi
          done
          
        else
      
          out="0"
      
          while [ ${out} -eq "0" ] ; do
        
            echo -e "\nPrinting all the connected drive(s):\n"
            lsblk -p
            echo
          
            read -r -p "Which drive do you want to partition? Please enter the full drive path (i.e. /dev/sda): " user_drive
    
            if [[ ! -e "${user_drive}" ]] ; then
              echo -e "\nPlease select a valid drive."
      
            else
          
              while true; do
              echo -e "\nYou selected ${user_drive}."
              echo -e "\nTHIS DRIVE WILL BE PARTITIONED, EVERY DATA INSIDE WILL BE LOST."
              read -r -p "Are you sure you want to continue? (y/n and [ENTER]): " yn
          
              if [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
                echo -e "\nAborting, select another drive."
                break
              elif [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
                if cat /proc/mounts | grep "${user_drive}" &> /dev/null ; then
                  echo -e -n "\nDrive already mounted.\nChanging directory to "${HOME}" and unmounting every partition before selecting it for partitioning...\n"
                  cd $HOME
                  umount -l "${user_drive}"?*
                  echo -e -n "\nDrive unmounted successfully.\n"
                fi

                echo -e "\nCorrect drive selected, back to tool selection..."
                out="1"
                break
              else
                echo -e "\nPlease answer y or n."
              fi
              done
            
            fi
          
          done
        
        fi
      
      done
    
    elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
      echo -e "\nNo additional changes were made."
      break
    
    else
      echo -e "\nPlease answer y or n."
    
    fi
  
  done
  
}

function disk_encryption () {

  out="0"

  while [ "${out}" -eq "0" ]; do
  
    echo -e -n "\nPrinting all the connected drives:\n\n"
    lsblk -p
    
    echo
    read -r -p "Which / [root] partition do you want to encrypt? Please enter the full partition path (i.e. /dev/sda1): " encrypted_partition
      
    if [[ ! -e "${encrypted_partition}" ]] ; then
      echo -e -n "\nPlease select a valid partition.\n"
      
    else
      while true; do
        echo -e -n "\nYou selected: ${encrypted_partition}.\n\n"
        read -r -p "Is this correct? (y/n and [ENTER]): " yn
        
        if [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
          echo -e -n "\nAborting, select another partition.\n"
          break
        elif [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
          echo -e -n "\nCorrect partition selected.\n"

          echo -e -n "\nKeep in mind that GRUB LUKS version 2 support is still limited.\n(https://savannah.gnu.org/bugs/?55093)\nChoosing it could result in an unbootable system.\nIt's strongly recommended to use LUKS version 1.\n"

          while true ; do
            echo -e -n "\nWhich LUKS version do you want to use? (1/2 and [ENTER]): "
            read ot
            if [[ "${ot}" == "1" ]] || [[ "${ot}" == "2" ]] ; then
              echo -e -n "\nUsing LUKS version "${ot}".\n\n"
              cryptsetup luksFormat --type=luks"${ot}" "${encrypted_partition}"
              break
            else
              echo -e -n "\nPlease enter 1 or 2.\n"
            fi
          done

          out1="0"

          while [ "${out1}" -eq "0" ] ; do
            echo -e -n "\nEnter a name for the encrypted partition without any spaces (i.e. MyEncryptedLinuxPartition): "
            read encrypted_name
            if [[ -z "${encrypted_name}" ]] ; then
              echo -e -n "\nPlease enter a valid name.\n"
            else
              while true ; do
                echo -e -n "\nYou entered: "${encrypted_name}".\n\n"
                read -n 1 -r -p "Is this the desired name? (y/n): " yn
          
                if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
                  echo -e -n "\n\nPartition will now be mounted as: /dev/mapper/"${encrypted_name}"\n\n"
                  cryptsetup open "${encrypted_partition}" "${encrypted_name}"
                  out1="1"
                  break
                elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
                  echo -e -n "\n\nPlease select another name.\n"
                  break
                else
                  echo -e "\n\nPlease answer y or n."
                fi
              done
            fi
          done

          out="1"
          break
        else
          echo -e -n "\nPlease answer y or n.\n"
        fi
      done

    fi
    
  done
 
}

function lvm_creation () {

  echo -e -n "\nCreating logical partitions wih LVM.\n"

  out1='0'

  while [ "${out1}" -eq "0" ] ; do

    out='0'

    while [ "${out}" -eq "0" ]; do

      echo -e -n "\nEnter a name for the volume group without any spaces (i.e. MyLinuxVolumeGroup): "
      read vg_name
    
      if [[ -z "${vg_name}" ]] ; then
        echo -e -n "\nPlease enter a valid name.\n"
      else
        while true ; do
          echo -e -n "\nYou entered: "${vg_name}".\n\n"
          read -n 1 -r -p "Is this the desired name? (y/n): " yn
          
          if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
            echo -e -n "\n\nVolume group will now be mounted as: /dev/mapper/"${vg_name}"\n\n"
            vgcreate "${vg_name}" /dev/mapper/"${encrypted_name}"
            out="1"
            break
          elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
            echo -e -n "\n\nPlease select another name.\n"
            break
          else
            echo -e "\n\nPlease answer y or n."
          fi

        done

      fi

    done

    out='0'

    while [ "${out}" -eq "0" ]; do

      echo -e -n "\nEnter a name for the logical root partition without any spaces and its size.\nBe sure to make no errors (i.e. MyLogicLinuxRootPartition 100G): "
      read lv_root_name lv_root_size
    
      if [[ -z "${lv_root_name}" ]] || [[ -z "${lv_root_size}" ]] ; then
        echo -e -n "\nPlease enter valid values.\n"
      else
        while true ; do
          echo -e -n "\nYou entered: "${lv_root_name}" and "${lv_root_size}".\n\n"
          read -n 1 -r -p "Are these correct? (y/n): " yn
          
          if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
            echo -e -n "\n\nLogical volume "${lv_root_name}" of size "${lv_root_size}" will now be created.\n\n"
            lvcreate --name "${lv_root_name}" -L "${lv_root_size}" "${vg_name}"
            out="1"
            break
          elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
            echo -e -n "\n\nPlease select other values.\n"
            break
          else
            echo -e "\n\nPlease answer y or n."
          fi

        done

      fi

    done

    out='0'

    while [ "${out}" -eq "0" ]; do

      echo -e -n "\nEnter a name for the logical home partition without any spaces.\nIts size will be the remaining free space (i.e. MyLogicLinuxHomePartition): "
      read lv_home_name
    
      if [[ -z "${lv_home_name}" ]] ; then
        echo -e -n "\nPlease enter a valid name.\n"
      else
        while true ; do
          echo -e -n "\nYou entered: "${lv_home_name}".\n\n"
          read -n 1 -r -p "Is this the desired name? (y/n): " yn
          
          if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
            echo -e -n "\n\nLogical volume "${lv_home_name}" will now be created.\n\n"
            lvcreate --name "${lv_home_name}" -l +100%FREE "${vg_name}"
            out="1"
            break
          elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
            echo -e -n "\n\nPlease select another name.\n"
            break
          else
            echo -e "\n\nPlease answer y or n."
          fi

        done

      fi

    done

    break

  done
  
}

# Main

check_if_bash
check_if_run_as_root
set_keyboard_layout
check_and_connect_to_internet
disk_wiping
disk_partitioning
disk_encryption
lvm_creation
