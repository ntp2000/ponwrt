#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Assemble the bootstrap with the native kernel cpio writer. The rootfs is the
# unmodified per-device squashfs already produced by OpenWrt's image rules.
set -eu

[ "$#" -eq 6 ] || {
	echo "Usage: $0 ROOT_DIR SQUASHFS INIT GEN_INIT_CPIO EPOCH OUTPUT" >&2
	exit 1
}
ramboot_root=$1
ramboot_squashfs=$2
ramboot_init=$3
ramboot_cpio=$4
ramboot_epoch=$5
ramboot_output=$6

for ramboot_file in bin/busybox lib/libc.so lib/libgcc_s.so.1 \
	lib/firmware/airoha/en7581_MT7916_npu_rv32.bin \
	lib/firmware/airoha/en7581_MT7916_npu_data.bin; do
	[ -s "$ramboot_root/$ramboot_file" ] || {
		echo "Missing recovery dependency: $ramboot_file" >&2
		exit 1
	}
done
[ -s "$ramboot_squashfs" ] && [ -s "$ramboot_init" ]
# Bound boot-time copies independently of the installed (uncompressed) size.
[ "$(wc -c < "$ramboot_squashfs")" -le 134217728 ] || {
	echo "RAM recovery squashfs exceeds the 128 MiB memory budget" >&2
	exit 1
}

ramboot_stage=$(mktemp -d "$ramboot_output.stage.XXXXXX")
trap 'rm -rf "$ramboot_stage"' EXIT HUP INT TERM
ramboot_list=$ramboot_stage/list
# mksquashfs uses -nopad. A loop device rounds its size down to whole sectors;
# without padding, the filesystem's bytes_used can exceed the block device.
# Match the page padding used by the native FIT rootfs image rule.
dd if="$ramboot_squashfs" of="$ramboot_stage/root.squashfs" bs=4096 conv=sync 2>/dev/null
cat > "$ramboot_list" <<EOF
dir /bin 0755 0 0
dir /dev 0755 0 0
dir /lib 0755 0 0
dir /lib/firmware 0755 0 0
dir /lib/firmware/airoha 0755 0 0
dir /proc 0555 0 0
dir /backing 0755 0 0
dir /new_root 0755 0 0
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
nod /dev/loop0 0600 0 0 b 7 0
nod /dev/loop-control 0600 0 0 c 10 237
file /bin/busybox $ramboot_root/bin/busybox 0755 0 0
file /lib/libc.so $ramboot_root/lib/libc.so 0755 0 0
file /lib/libgcc_s.so.1 $ramboot_root/lib/libgcc_s.so.1 0644 0 0
file /lib/firmware/airoha/en7581_MT7916_npu_rv32.bin $ramboot_root/lib/firmware/airoha/en7581_MT7916_npu_rv32.bin 0644 0 0
file /lib/firmware/airoha/en7581_MT7916_npu_data.bin $ramboot_root/lib/firmware/airoha/en7581_MT7916_npu_data.bin 0644 0 0
slink /lib/ld-musl-aarch64.so.1 libc.so 0777 0 0
file /init $ramboot_init 0755 0 0
file /root.squashfs $ramboot_stage/root.squashfs 0644 0 0
EOF
for ramboot_applet in sh mount mkdir mv sleep switch_root; do
	echo "slink /bin/$ramboot_applet busybox 0777 0 0" >> "$ramboot_list"
done
"$ramboot_cpio" -t "$ramboot_epoch" "$ramboot_list" > "$ramboot_output"
