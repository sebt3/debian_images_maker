#!/bin/bash
#@DESC@ Nano-PC T4 (www.friendlyarm.com) images
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

VLAN=${VLAN:-"192.168.10"}
LIP=${LIP:-"10"}
args.declare VLAN    -v --vlan      Vals NoOption NotMandatory "3 first numbers for the vlan	(DEFAULT: $VLAN)"
args.declare LIP     -i --last-ip   Vals NoOption NotMandatory "last ip number for that vm	(DEFAULT: $LIP)"

ARCH=arm64

##############################################################################
### Setup
##

# install android-tools-fsutils for make_ext4fs and img2simg
setup.device() {
	task.add setup.nano.base		"Install android-tools-fsutils"
}

setup.nano.base() {
	out.cmd apt-get -y install android-tools-fsutils
}


##############################################################################
### Image prepare
##

image.prepare() {
	IMAGE="${IMAGEDIR}/${HNAME}.raw.img"
	task.add prepare.mkfs		"Make the empty raw image file"
	task.add prepare.mount		"Mount the OS filesystem"
}

prepare.mkfs.precheck() {	precheck.root; }
prepare.mkfs() {
	[ -f "$IMAGE" ] && file "$IMAGE"|awk 'BEGIN{R=1}/ext4 filesystem data/{R=0}END{exit R}' && return 0
	local tmp=$(tempfile) r=0
	rm $tmp
	mkdir $tmp
	make_ext4fs -l ${OSSIZE:-"2G"} -a root -L rootfs ${IMAGE} $tmp
	r=$?
	rmdir $tmp
	return $r
}
prepare.mount.precheck() {	precheck.root; }
prepare.mount() {
	mkdir -p "$OSROOT"
	out.cmd mount -oloop "$IMAGE" "$OSROOT"
}


##############################################################################
### Image install
##

image.install() {
	task.add install.base		"Install the kernel and base tools"
	task.add install.config		"Configure the network"
}

install.base.precheck() {	precheck.root; }
install.base.verify() { task.verify.permissive; }
install.base() {
	apt.install gnupg2
	apt.install vim openssh-server net-tools iw rfkill wpasupplicant alsa-utils ifupdown resolvconf pciutils ethtool dnsutils vlan
}
install.config() {
	cat <<EOF > "$OSROOT/etc/network/interfaces.d/eth0"
auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
EOF
	cat <<EOF > "$OSROOT/etc/network/interfaces.d/private"
auto eth0.100
iface eth0.100 inet static
  vlan-raw-device eth0
  address ${VLAN}.$LIP
  netmask 255.255.255.0
EOF
}

##############################################################################
### Image finish
##
image.finish() {
	IMAGE="${IMAGEDIR}/${HNAME}.img"
	task.add finish.umount		"umount the root filesystem"
}

finish.umount() {
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P"/dev"{R=1}END{exit R}' || umount "$OSROOT/dev"
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P"/proc"{R=1}END{exit R}' || umount "$OSROOT/proc"
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P"/sys"{R=1}END{exit R}' || umount "$OSROOT/sys"
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P"/etc/machine-id"{R=1}END{exit R}' || umount "$OSROOT/etc/machine-id"
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P{R=1}END{exit R}' || umount "$OSROOT"
}

##############################################################################
### Image load
##
image.load() {
	:
}
