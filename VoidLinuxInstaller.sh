#! /bin/bash

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

  read -n 1 -r -p "Press any key to list all the keyboard layouts, move with arrow keys and press \"q\" to exit the list." key
  ls --color=always -laR /usr/share/kbd/keymaps/ | less --RAW-CONTROL-CHARS --no-init
  
  echo -e "\nTo set a keyboard layout, write its name, without \".map.gz\" (i.e. us.map.gz -> us).\n"
  
  while true ; do
    read -p "Choose the keyboard layout you want to set and press [ENTER] or press [ENTER] to keep the one currently set: " user_keyboard_layout
  
    if [[ -z "${user_keyboard_layout}" ]]; then
      echo -e "\nNo keyboard layout selected, keeping the previous one."
      break
    else
      if loadkeys ${user_keyboard_layout} 2>/dev/null ; then
        echo -e "\nKeyboad layout set to \"${user_keyboard_layout}\"."
        break
      else
        echo -e "\nNot a valid keyboard layout, please try again.\n"
      fi
    fi
  done

}

function connect_to_wifi () {

  declare wifi_interface
  declare wifi_essid
  declare wifi_passphrase
  
  echo -e "\nChecking internet connectivity..."
  
  if ! ping -c2 8.8.8.8 > /dev/null ; then
    echo -e "\nNo internet connection found."
    
    if [[ -e /var/service/NetworkManager ]] ; then
    
      while true; do
        echo -e -n "\nEnter your ESSID and press [ENTER]: "
        read wifi_essid
        
        if [[ ! -z "${wifi_essid}" ]]; then
          read -n 1 -r -p "Is your ESSID hidden? (y/n): " yn
            if [[ "${yn}" == "y" ]] || [[ "${yn}" == "Y" ]] ; then
              nmcli --ask device wifi connect ${wifi_essid} hidden yes
              break
            else
              nmcli --ask device wifi connect ${wifi_essid}
              break
            fi
        else
          echo -e "\nPlease enter a valid ESSID."
        fi
      done
      
    else
      ip a
      
      while true; do
        echo -e -n "\nEnter the wifi interface and press [ENTER]: "
        read wifi_interface
      
        if [[ ! -z "${wifi_interface}" ]]; then
          echo -e -n "\nEnter your ESSID and press [ENTER]: "
          read wifi_essid
          
          if [[ -d /etc/wpa_supplicant/ ]]; then
            continue
          else
            mkdir -p /etc/wpa_supplicant/
          fi
          
          echo -e "\nConnecting to wifi..."
          wpa_passphrase "${wifi_essid}" | tee /etc/wpa_supplicant/wpa_supplicant.conf
          wpa_supplicant -B -c /etc/wpa_supplicant/wpa_supplicant.conf -i "${wifi_interface}"
        else
          echo -e "\nPlease input a valid wifi interface."
        fi
      done
      
     fi
    
    if ping -c2 8.8.8.8 > /dev/null ; then
      echo -e "\nSuccessfully connected to the internet."
    fi
    
  else
    echo -e "\nAlready connected to the internet."
  fi

}

function copy_wifi_configuration_files () {

  echo -e "\nTO BE COMPLETED\n"

}


# Main

check_if_bash
check_if_run_as_root
set_keyboard_layout
connect_to_wifi
copy_wifi_configuration_files
