# VoidLinuxInstaller script

The **VoidLinuxInstaller script** is an attempt to make [my gist](https://gist.github.com/Le0xFF/ff0e3670c06def675bb6920fe8dd64a3) an interactive bash script.

As stated in the gist, this script provides:
- Full Disk Encryption (including `/boot`) with LUKS;
- Logic Volume Management (LVM);
- Separated `/home` partition;
- BTRFS as filesystem.
- Trim on SSD;

To know how the script works in details, please jump to the [How does it work?](#how-does-it-work) section!

To know how to run the script, please jump to the [How to run it?](#how-to-run-it) section!

This script comes from my need to automate my gist as much as I can, and also as a way to learn Bash scripting as well. *This is my first Bash script ever created so bugs, errors and really ugly code are expected!*

I've tried this script a lot with virtual machines and following every step always brought me to a functional system, so there should be no problem from this point of view!

Pull requests are absolutely welcome!

<br>

## How to run it?

Using wget to download the needed file:

``` bash
wget https://raw.githubusercontent.com/Le0xFF/VoidLinuxInstaller/main/VoidLinuxInstaller.sh -O $HOME/VoidLinuxInstaller.sh
```

or curl if you prefer:

``` bash
curl -o $HOME/VoidLinuxInstaller.sh https://raw.githubusercontent.com/Le0xFF/VoidLinuxInstaller/main/VoidLinuxInstaller.sh
```

then make it executable:

``` bash
chmod +x $HOME/VoidLinuxInstaller.sh
```

and finally run it:

``` bash
bash $HOME/VoidLinuxInstaller.sh
```

<br>

## How does it work?

Here is documented how the script works in details and what will ask to the user in each different step. It will:

1. prompt the user to eventually change their keyboard layout from a list of all the different available layouts.
2. check internet connection and eventually guide the user to connect to the internet;
3. wipe a user choosen drive and that drive will be the one also selected for partitioning;
4. partition a user choosen drive:
    - if the previous drive was not the right one, it will ask the user if they want to change it eventually;
    - check the [Suggested partition layout](#suggested-partition-layout) to follow the script workflow;
5. encrypt a user choosen partition for Full Disk Encryption:
    - it will ask for a mountpoint name, so that the encrypted partition will be mounted as  
    `/dev/mapper/<encrypted_name>`;
6. apply Logical Volume Management to the previous encrypted partition, to have the flexibility to resize `/` and `/home` partitions without too much hassle:
    - it will ask for a Volume Group name, so that will be mounted as  
    `/dev/mapper/<volume_group>`;
    - it will ask for a Logical Volume name for **root** partition, and also for its size, so that will be mounted as  
    `/dev/mapper/<volume_group>-<root_name>`;
    - it will ask for a Logical Volume name for **home** partition; the remaining free space will be used for it and it will be mounted as  
    `/dev/mapper/<volume_group>-<home_name>`
    - check the [Final partitioning result](#final-partitioning-result) to get an overview of what the outcome will be;
7. Formatting partitions to proper filesystems:
    - it will prompt user to select which partition to use as **boot** partition and to choose its label; it will be formatted as FAT32 and mounted as  
    `/boot/efi`;
    - it will prompt user to select a label for the **root** logical partition, that will be formatted as BTRFS;
    - it will prompt user to select a label for the **home** logical partition, that will be formatted as BTRFS;
8. create BTRFS subvolumes with specific fstab mount options; if user wants to change them, please edit the script, looking for `create_btrfs_subvolume` function ([BTRFS mount options official documentation](https://btrfs.readthedocs.io/en/latest/btrfs-man5.html#mount-options)):
    - **BTRFS mounting options**:
        * `rw,noatime,ssd,compress=zstd,space_cache=v2,commit=120`
    - **BTRFS subvolumes that will be created**:
        * `/@`
        * `/@snapshots`
        * `/home/@home`
        * `/var/cache/xbps`
        * `/var/tmp`
        * `/var/log`
9. install base system:
    - It will ask user to choose between `x86_64` and `x86_64-musl`;
10. chroot:
    * set *root* password and `/` permissions;
    * create proper `/etc/fstab` file;
    * generate random key to avoid typing password two times at boot;
    * create proper dracut configuration and initramfs;
    * install grub;
    * enable internet at first boot with NetworkManager.

### Suggested partition layout

To have a smooth script workflow, the following is the suggested disk layout:

- GPT as disk label type for UEFI systems, also because this script will only works on UEFI systems;
- Less than 1 GB for `/boot/efi` as first partition, as EFI System type;
- Rest of the disk for the Volume Group, that will be logically partitioned with LVM (`/` and `/home`), as second partition as Linux filesystem.

Those two will be physical partition.  
You don't need to create a `/home` partition now because it will be created later as a logical one with LVM.

### Final partitioning result

Following the script, at the very end your drive will end up being like the following:

``` bash
/dev/nvme0n1                                 259:0    0 953,9G  0 disk  
├─/dev/nvme0n1p1                             259:1    0     1G  0 part  /boot/efi
├─/dev/nvme0n1p2                             259:2    0 942,9G  0 part  
│ └─/dev/mapper/<encrypted_name>             254:0    0 942,9G  0 crypt 
│   └─/dev/mapper/<volume_group>-<root_name> 254:1    0 942,9G  0 lvm   /.snapshots
|   |                                                                   /
│   └─/dev/mapper/<volume_group>-<home_name> 254:1    0 942,9G  0 lvm   /home
```

<br>

## Notes

- If you are going to use snapper and [snapper-gui](https://github.com/ricardomv/snapper-gui), it probably will complain about `/.snapshots` folder already present.  
To avoid that, please use [this reference from the Arch Wiki](https://wiki.archlinux.org/title/Snapper#Configuration_of_snapper_and_mount_point).

<br>

## Resources

[1] https://tldp.org/LDP/Bash-Beginners-Guide/html/index.html  
[2] https://gist.github.com/tobi-wan-kenobi/bff3af81eac27e210e1dc88ba660596e  
[3] https://gist.github.com/gbrlsnchs/9c9dc55cd0beb26e141ee3ea59f26e21  
[4] https://unixsheikh.com/tutorials/real-full-disk-encryption-using-grub-on-void-linux-for-bios.html
