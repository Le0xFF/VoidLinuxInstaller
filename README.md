# VoidLinuxInstaller script

The **VoidLinuxInstaller script** is an attempt to make [my gist](https://gist.github.com/Le0xFF/ff0e3670c06def675bb6920fe8dd64a3) an interactive bash script.

As stated in the gist, this script provides:
- Trim on any SSD;
- Full Disk Encryption (including /boot) with LUKS;
- Logic Volume Management (LVM);
- Separated /home partition;
- BTRFS as filesystem.

All of this is accomplished with the following steps:
1. Changing keyboard layout;
2. Checking internet connection;
3. Wiping a user choosen drive;
3. Partitioning a user choosen drive;
4. Encrypting a user choosen drive;
5. Applying LVM;
6. Formatting partitions to proper filesystems;
7. Creating BTRFS subvolumes;
8. Installing base system;
9. Chrooting.

This script comes from my need to automate my gist as much as I can, and also as a way to learn Bash scripting as well.
*This is my first Bash script ever created so bugs, errors and really ugly code are expected!*

I've tried this script a lot with KVM and following every step always brought me to a functional system, so there should be no problem from this point of view!

Pull requests are absolutely welcome!

# Notes

If you are going to use snapper and [snapper-gui](https://github.com/ricardomv/snapper-gui), it probably will complain about `.snapshots` folder already present.
To avoid that, please use [this reference from the Arch Wiki](https://wiki.archlinux.org/title/Snapper#Configuration_of_snapper_and_mount_point).

# Resources

[1] https://tldp.org/LDP/Bash-Beginners-Guide/html/index.html
[2] https://gist.github.com/tobi-wan-kenobi/bff3af81eac27e210e1dc88ba660596e
[3] https://gist.github.com/gbrlsnchs/9c9dc55cd0beb26e141ee3ea59f26e21
[4] https://unixsheikh.com/tutorials/real-full-disk-encryption-using-grub-on-void-linux-for-bios.html
