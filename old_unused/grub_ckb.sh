#! /bin/sh
#
# Create grubx64.efi containing custom keyboard layout
# Requires: ckbcomp, grub2, xkeyboard-config
#

if [ ! -f /boot/efi/EFI/$bootloader_id/ORIG_grubx64.efi_ORIG ] ; then
    if [ ! -d /boot/grub/ ] || [ ! -f /boot/efi/EFI/$bootloader_id/grubx64.efi ] ; then
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
