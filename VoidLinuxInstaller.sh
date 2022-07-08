#! /bin/bash

# Variables

user_drive=''

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
      
          if loadkeys ${user_keyboard_layout} 2>/dev/null ; then
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
  
    echo
    read -n 1 -r -p "Do you want to connect to the internet? (y/n): " yn
    
    if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
  
      echo -e "\n\nChecking internet connectivity..."
    
      if ! ping -c2 8.8.8.8 &> /dev/null ; then
        echo -e -n "\nNo internet connection found. Do you want to use wifi? (y/n): "
        read -n 1 yn
    
        if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
      
          if [[ -e /var/service/NetworkManager ]] ; then
        
            while true; do
          
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
                 echo -e "\nPlease answer y or n."
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
          echo -e -n "\nPlease connect your ethernet cable and wait a minute before pressing any key."
          read -n 1 -r wait
      
        else
          echo -e "\nPlease answer y or n."
        fi
      
      else
        echo -e "\nAlready connected to the internet."
        break
      fi
    
    elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
      echo -e "\n\nChecking if already connected..."
      if ping -c2 8.8.8.8 &> /dev/null ; then
        echo -e "\nYou are already connected to the internet."
        echo -e "If you don't want to be online, please unplug your ethernet cable or disconnect your wifi."
        break
      else
        echo -e "\nYou are not connected to the internet, continuing..."
      fi
    
    else
      echo -e "\nPlease answer y or n."
    fi
    
  done

}

function disk_wiping () {
  
  while true; do
  
    echo
    read -n 1 -r -p "Do you want to wipe any drive? (y/n): " yn
    
    if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
      
      out="0"
      
      while [ ${out} -eq "0" ] ; do
      
        echo -e "\nPrinting all the connected drive(s):\n"
        lsblk -p
    
        echo
        read -r -p "Which drive do you want to wipe? Please enter the full path (i.e. /dev/sda): " user_drive
      
        if [[ ! -e "${user_drive}" ]] ; then
          echo -e "\nPlease select a valid drive."
      
        else
          while true; do
          echo -e "\nYou selected ${user_drive}."
          echo -e "\nTHIS DRIVE WILL BE WIPED, EVERY DATA INSIDE WILL BE LOST."
          read -r -p "Are you sure you want to continue? (y/n and [ENTER]): " yn
        
          if [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
            echo -e "\nAborting, select another drive."
            break
          elif [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
            echo -e "\nWiping the drive...."
            wipefs -a "${user_drive}"
            out="1"
            break
          else
            echo -e "\nPlease answer y or n."
          fi
          done
        fi
      done
      
    elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
      echo -e "\n\nNo drive wiped."
      break
    
    else
      echo -e "\n\nPlease answer y or n."
    fi
  
  done
}

function disk_partitioning () {
  
  while true; do
  
    echo -e -n "\nIf you already partitioned any drive, select \"n\"\n"
    read -n 1 -r -p "Do you want to partition any drive? (y/n): " yn
    echo
    
    if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
    
      if [[ ! -z "${user_drive}" ]] ; then
      
        while true; do
          
          echo -e -n "\nSuggested disk layout:"
          echo -e -n "\n- Less than 1 GB for /boot/efi partition [EFI System];"
          echo -e -n "\n- Rest of the disk for / partition [Linux filesystem]."
          echo -e -n "\n\nThose two will be physical partition.\nYou don't need to create a /home partition now because it will be created later as a logical one.\n"
          
          echo -e -n "\nDrive selected for partitioning: ${user_drive}\n\n"
          
          read -r -p "Which tool do you want to use? (fdisk/cfdisk/sfdisk): " tool
      
          case "${tool}" in
            fdisk)
              fdisk "${user_drive}"
              ;;
            cfdisk)
              cfdisk "${user_drive}"
              ;;
            sfdisk)
              sfdisk "${user_drive}"
              ;;
            *)
              echo -e -n "\nPlease select only one of the three suggested tools."
              ;;
          esac
          
          echo
          lsblk -p "${user_drive}"
          echo
          read -n 1 -r -p "Is this partition table okay? (y/n): " yn
          
          if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
            echo -e -n "\n\nDrive partitioned, keeping changes.\n"
            break
          elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
            echo -e -n "\n\nPlease partition your drive again.\n"
          else
            echo -e "\nPlease answer y or n."
          fi
          
        done
        
      else
      
        while true; do
        
          echo -e "\nPrinting all the connected drive(s):\n"
          lsblk -p
          echo
          
          read -r -p "Which drive do you want to partition? Please enter the full path (i.e. /dev/sda): " user_drive
    
          if [[ ! -e "${user_drive}" ]] ; then
            echo -e "\nPlease select a valid drive."
      
          else
            echo -e "\nYou selected ${user_drive}."
            echo -e "\nTHIS DRIVE WILL BE PARTITIONED, EVERY DATA INSIDE WILL BE LOST."
            read -r -p "Are you sure you want to continue? (y/n and [ENTER]): " yn
          
            if [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
              echo -e "\nAborting, select another drive."
            elif [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
              echo -e "\nCorrect drive selected, no partitioning performed, back to tool selection..."
              break
            else
              echo -e "\nPlease answer y or n."
            fi
            
          fi
          
        done
        
      fi
    
    elif [[ "${yn}" == "n" ]] || [[ "${yn}" == "N" ]] ; then
      echo -e "\nNo additional changes were made."
      break
    
    else
      echo -e "\nPlease answer y or n."
    fi
  
  done
  
}

# Main

check_if_bash
check_if_run_as_root
set_keyboard_layout
check_and_connect_to_internet
disk_wiping
disk_partitioning
