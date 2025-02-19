#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Run this script as root"
  exit
fi


rm -rf rootfs
rm rootfs.cpio.gz
mkdir rootfs
mkdir rootfs/dev

if test ! -f apk.static; then
    wget -nc https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic//v2.14.10/x86_64/apk.static
    chmod +x apk.static
fi

pkgs="$(cat packages | tr '\n' ' ')"

echo "Packages: $pkgs"

mount --bind /dev rootfs/dev

./apk.static --arch armv7 -X http://dl-cdn.alpinelinux.org/alpine/edge/main/ \
    -X https://dl-cdn.alpinelinux.org/alpine/edge/community \
    -U --allow-untrusted --root rootfs --no-cache --initdb add $pkgs

echo 'export "PATH=/usr/bin:/usr/sbin:/bin:/sbin"' >> /etc/profile

mkdir -p rootfs/lib/firmware/wlan/prima
cp fw/* rootfs/lib/firmware/ 2>/dev/null
cp fw/wlan/* rootfs/lib/firmware/wlan/prima

mkdir -p "rootfs/etc/network"
cat <<- EOF > "rootfs/etc/network/interfaces"
auto lo
iface lo inet loopback
EOF

add() {
	chroot rootfs /sbin/rc-update add "$1" "$2"
}

add devfs sysinit
add dmesg sysinit
add mdev sysinit
add hwdrivers sysinit

add sysctl boot
add bootmisc boot
add syslog boot

add udev sysinit
add udev-trigger sysinit
add udev-settle sysinit
add udev-postmount default
add hostname boot
add networking default
add iwd default
add dbus default

add local default

chroot rootfs /bin/sh -c 'export PATH="/usr/bin:/usr/sbin:/bin:/sbin";
ln -s /bin/sh /init;
dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key'

sed -i 's/#\?ttyS0/ttyMSM0/g' rootfs/etc/inittab
echo "ttyMSM0" >> rootfs/etc/securetty

umount -R rootfs/dev && rm -rf rootfs/dev

cd rootfs
chown -h -R 0:0 .
find . | LC_ALL=C sort | cpio -o --format=newc | gzip -9 > ../rootfs.cpio.gz
cd ..

du -h rootfs.cpio.gz
