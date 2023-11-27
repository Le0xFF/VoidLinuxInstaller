# Old or unused files

This folder contains old files or unused files, but that are handy to keep stored somewhere.

The `chroot.sh` script is an old version of a script meant to be run during Void Linux installation that got merged into the main installation script.

The `btrfs_map_physical.c` is a C program, useful to find physical offset for the swapfile, mentioned in the [Arch Wiki](https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate#Hibernation_into_swap_file_on_Btrfs). The program got also merged into the main installation script.  
I'm not the developer of this program, the original script can be found in [this repo](https://github.com/osandov/osandov-linux); I just copied it here with its MIT license.

Since version 6.1, `btrfs_map_physical.c` is not needed anymore. `btrfs-progs` now offers:
* `btrfs filesystem mkswapfile swapfile` to create the swapfile;
* `btrfs inspect-internal map-swapfile swapfile` to print the device physical offset and the adjusted value for `/sys/power/resume_offset`. Note that the value is divided by page size.
    + For scripting and convenience the option -r will print just the offset: `btrfs inspect-internal map-swapfile -r swapfile`
