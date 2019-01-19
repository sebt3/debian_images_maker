#!/bin/bash
#@DESC@ Rock64 (www.pine64.org) images
# BSD 3-Clause License
# 
# Copyright (c) 2018, Sébastien Huss
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

##############################################################################
### Arguments
##

TARGET=${TARGET:-"/dev/sdb"}
args.declare TARGET    -T --target      Vals NoOption NotMandatory "The device to flash to	(DEFAULT: $TARGET)"

ARCH=arm64

##############################################################################
### Setup
##

setup.device() {
	:
}


##############################################################################
### Image prepare
##

image.prepare() {
	IMAGE="${IMAGEDIR}/${HNAME}.raw"
	task.add prepare.file		"Create the image file"
	task.add prepare.mkfs		"Make the OS filesystem"
	task.add prepare.mount		"Mount the OS filesystem"
}

prepare.file() {
	[ -f "$IMAGE" ] && file "$IMAGE"|awk 'BEGIN{R=1}/QEMU QCOW/{R=0}END{exit R}' && return 0
	out.cmd qemu-img create -f raw "$IMAGE" ${OSSIZE:-"2G"}
	sync
	sleep 2
	sync
}
prepare.mkfs.precheck() {	precheck.root; }
prepare.mkfs() {
	out.cmd mkfs.ext4 -L "linux-root" -qDF -E nodiscard "$IMAGE"
}
prepare.mount.precheck() {	precheck.root; }
prepare.mount() {
	mkdir -p "$OSROOT"
	out.cmd mount -oloop "$IMAGE" "$OSROOT"
	#mkdir -p "$OSROOT/boot/efi"
}


##############################################################################
### Image install
##

image.install() {
	task.add install.kernel		"Install the kernel and base tools"
	task.add install.config		"Configure the network"
}

install.kernel.precheck() {	precheck.root; }
install.kernel.verify() { task.verify.permissive; }
install.kernel() {
	apt.install gnupg2
	echo "deb http://deb.ayufan.eu/orgs/ayufan-rock64/releases /" >"$OSROOT/etc/apt/sources.list.d/rock64.list"
	curl -s http://deb.ayufan.eu/orgs/ayufan-rock64/archive.key | apt.key
	image.chroot apt-get update
	apt.install vim openssh-server linux-rock64 net-tools iw rfkill wpasupplicant alsa-utils flash-kernel u-boot-tools ifupdown resolvconf pciutils ethtool dnsutils linux-image-4.4.77-rockchip-ayufan-136
	# firmware-realtek firmware-brcm80211
}
install.config() {
	echo "Pine64 Rock64" > "$OSROOT/etc/flash-kernel/machine"
	echo "LABEL=boot /boot/efi vfat defaults,sync 0 0" > "$OSROOT/etc/fstab"
	cat >"$OSROOT/root/.bashrc" <<ENDF
export LS_OPTIONS='--color=auto'
eval "`dircolors`"
alias ls='ls \$LS_OPTIONS'
alias ll='ls \$LS_OPTIONS -l'

ENDF
	cat <<EOF > "$OSROOT/etc/network/interfaces.d/eth0"
auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
EOF
}

##############################################################################
### Image finish
##
image.finish() {
	task.add finish.umount		"umount the root filesystem"
	#task.add finish.disconnect	"Disconnect the image disk"
}

finish.umount() {
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P"/dev"{R=1}END{exit R}' || umount "$OSROOT/dev"
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P"/proc"{R=1}END{exit R}' || umount "$OSROOT/proc"
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P"/sys"{R=1}END{exit R}' || umount "$OSROOT/sys"
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P"/etc/machine-id"{R=1}END{exit R}' || umount "$OSROOT/etc/machine-id"
	#mount|awk -vR=0 "-vP=$OSROOT" '$3==P"/boot/efi"{R=1}END{exit R}' || umount "$OSROOT/boot/efi"
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P{R=1}END{exit R}' || umount "$OSROOT"
}
finish.disconnect() {
	fuser "$DISK" >/dev/null 2>&1 || return 0
	blockdev --flushbufs "$DISK"
	out.cmd qemu-nbd -d "$DISK"
}

##############################################################################
### Image load
##
image.load() {
	IMAGE="${IMAGEDIR}/${HNAME}.raw"
	task.add load.flash		"Flash the root FS"
	task.add load.resize		"Resize the root FS"
}
load.flash() {
	out.cmd dd if=$IMAGE of=${TARGET}7 #status=progress
}
load.resize() {
	out.cmd e2fsck -fy "${TARGET}7"
	out.cmd resize2fs "${TARGET}7"
	blockdev --flushbufs /dev/sdb
	sync
}
