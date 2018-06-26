#!/bin/bash
#@DESC@ KVM vm images templates
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

ARCH=${ARCH:-"$(dpkg --print-architecture)"}
DISK=${DISK:-"/dev/nbd0"}
VLAN=${VLAN:-"10.0.0"}
LIP=${LIP:-"10"}
MEM=${MEM:-"524288"}
args.declare ARCH    -A --arch      Vals NoOption NotMandatory "Architecture to build for	(DEFAULT: $ARCH)"
args.declare DISK    -d --disk      Vals NoOption NotMandatory "The nbd device to use	(DEFAULT: $DISK)"
args.declare VLAN    -v --vlan      Vals NoOption NotMandatory "3 first numbers for the vlan	(DEFAULT: $VLAN)"
args.declare LIP     -i --last-ip   Vals NoOption NotMandatory "last ip number for that vm	(DEFAULT: $LIP)"
args.declare MEM     -E --mem       Vals NoOption NotMandatory "VM memory			(DEFAULT: $MEM)"

##############################################################################
### Setup
##

setup.device() {
	task.add setup.install "Install base packages for the host"
	task.add setup.netdef  "Create the private network"
	task.add setup.netconf "Configure the private network"
}


setup.install.precheck() {	precheck.root; }
setup.install() {
	out.cmd apt-get install -y bridge-utils qemu-kvm libvirt-clients libvirt-daemon-system debianutils grub2-common curl libxml-xpath-perl dpkg-dev
}

setup.netdef.precheck() {	precheck.root; }
setup.netdef() {
	local F=$(tempfile) R=0
	virsh net-info private >/dev/null 2>&1 && return 0
	cat >$F <<ENDXML
<network>
  <name>private</name>
  <forward dev='eth0' mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
    <interface dev='eth0'/>
  </forward>
  <bridge name='br0' stp='on' delay='0'/>
  <domain name='private'/>
  <ip address='${VLAN}.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='${VLAN}.100' end='${VLAN}.254'/>
    </dhcp>
  </ip>
</network>
ENDXML
	virsh net-define $F
	R=$?
	rm $F
	return $R
}
setup.netdef.verify() {
	if ! virsh net-info private >/dev/null 2>&1 ;then
		out.error "The private network is not defined"
		return 1
	fi
	task.verify 
}

setup.netconf.precheck() {	precheck.root; }
setup.netconf() {
	virsh net-list|awk 'BEGIN{R=1}$1=="private"&&$2=="active"{R=0}END{exit R}' || virsh net-start private
	virsh net-list|awk 'BEGIN{R=1}$1=="private"&&$3=="yes"{R=0}END{exit R}' || virsh net-autostart private
}
setup.netconf.verify() {
	if ! virsh net-list|awk 'BEGIN{R=1}$1=="private"&&$3=="yes"{R=0}END{exit R}' ;then
		out.error "The private network is not set to autostart"
		return 1
	fi
	if ! virsh net-list|awk 'BEGIN{R=1}$1=="private"&&$2=="active"{R=0}END{exit R}' ;then
		out.error "The private network is not started"
		return 1
	fi
	task.verify 
}

##############################################################################
### Image prepare
##

image.prepare() {
	IMAGE="${IMAGEDIR}/${HNAME}.qcow"
	task.add prepare.loadnbd	"Load the nbd kernel module"
	task.add prepare.file		"Create the image file"
	task.add prepare.filenbd	"Bind the image as a drive"
	task.add prepare.partition	"Create the partition table"
	task.add prepare.mkfs		"Make the OS filesystem"
	task.add prepare.mount		"Mount the OS filesystem"
}

prepare.loadnbd.precheck() {	precheck.root; }
prepare.loadnbd() {
	lsmod|awk -vR=1 '$1=="nbd"{R=$3}END{exit R}' && rmmod nbd
	lsmod|awk -vR=1 '$1=="nbd"{R=$3}END{exit R}' && return 0
	out.cmd modprobe nbd nbds_max=2 max_part=10
}
prepare.file() {
	[ -f "$IMAGE" ] && file "$IMAGE"|awk 'BEGIN{R=1}/QEMU QCOW/{R=0}END{exit R}' && return 0
	out.cmd qemu-img create -f qcow2 "$IMAGE" ${OSSIZE:-"10G"}
	sync
	sleep 2
	sync
}
prepare.filenbd() {
	if [ ! -f "$IMAGE" ] || file "$IMAGE"|awk 'BEGIN{R=0}/QEMU QCOW/{R=1}END{exit R}';then
		out.error "$IMAGE is not a qcow file"
		return 1
	fi
	if file "$DISK"|awk 'BEGIN{R=0}/block special \(43/{R=1}END{exit R}';then
		out.error "$DISK is not an nbd block device"
		return 2
	fi
	fuser "$DISK" >/dev/null 2>&1 && return 0
	out.cmd qemu-nbd -n --fork -c "$DISK" "$IMAGE"
}
prepare.partition.precheck() {	precheck.root; }
prepare.partition() {
	echo ';'|sfdisk -q -f "$DISK"
	blockdev --flushbufs "$DISK"
	sync
}
prepare.mkfs.precheck() {	precheck.root; }
prepare.mkfs() {
	out.cmd mkfs.ext4 -qDF -E nodiscard "${DISK}p1"
	blockdev --flushbufs "$DISK"
	sync
}
prepare.mount.precheck() {	precheck.root; }
prepare.mount() {
	mkdir -p "$OSROOT"
	out.cmd mount "${DISK}p1" "$OSROOT"
}


##############################################################################
### Image install
##

image.install() {
	task.add install.kernel		"Install the kernel and base tools"
	task.add install.config		"Configure the network"
	task.add install.grub		"Install grub"
}

install.kernel.precheck() {	precheck.root; }
install.kernel.verify() { task.verify.permissive; }
install.kernel() {
	apt.install vim openssh-server acpid "linux-image-$ARCH" grub-pc net-tools
}
install.config() {
	cat <<EOF > "$OSROOT/etc/network/interfaces.d/ens3"
auto ens3
iface ens3 inet static
	address ${VLAN}.$LIP
	netmask 255.255.255.0
	gateway ${VLAN}.1
EOF
	cat <<EOF > "$OSROOT/etc/resolv.conf"
domain private
search private
nameserver ${VLAN}.1
EOF
}

install.grub() {
	if ! image.chroot grub-install "$DISK" 2>&1;then
		out.error "Failed to install grub"
		return 1
	fi
	if ! image.chroot update-grub 2>&1;then
		out.error "Failed to update grub"
		return 2
	fi
	sed -i "s|${DISK}p1|/dev/vda1|g" "$OSROOT/boot/grub/grub.cfg"
}

##############################################################################
### Image finish
##
image.finish() {
	task.add finish.umount		"umount the root filesystem"
	task.add finish.disconnect	"Disconnect the image disk"
}

finish.umount() {
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P"/dev"{R=1}END{exit R}' || umount "$OSROOT/dev"
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P"/proc"{R=1}END{exit R}' || umount "$OSROOT/proc"
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P"/sys"{R=1}END{exit R}' || umount "$OSROOT/sys"
	mount|awk -vR=0 "-vP=$OSROOT" '$3==P{R=1}END{exit R}' || umount "${DISK}p1"
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
	IMAGE="${IMAGEDIR}/${HNAME}.qcow"
	task.add load.xml		"Load the VM image in KVM"
	task.add load.start		"Start the VM"
}
load.start() {
	out.cmd virsh start "$HNAME"
}
load.xml() {
	local F=$(tempfile) R=0
	virsh dumpxml "$HNAME" >/dev/null 2>&1 && return 0
	cat >$F <<ENDXML
<domain type='kvm'>
  <name>$HNAME</name>
  <memory unit='KiB'>$MEM</memory>
  <vcpu placement='static'>1</vcpu>
  <os>
    <type arch='x86_64' machine='pc-i440fx-2.11'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <vmport state='off'/>
  </features>
  <cpu mode='custom' match='exact' check='partial'>
    <model fallback='allow'>Skylake-Client</model>
  </cpu>
  <clock offset='utc'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <pm>
    <suspend-to-mem enabled='no'/>
    <suspend-to-disk enabled='no'/>
  </pm>
  <devices>
    <emulator>/usr/bin/kvm</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$IMAGE'/>
      <target dev='vda' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </disk>
    <controller type='usb' index='0' model='ich9-ehci1'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x7'/>
    </controller>
    <controller type='usb' index='0' model='ich9-uhci1'>
      <master startport='0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0' multifunction='on'/>
    </controller>
    <controller type='usb' index='0' model='ich9-uhci2'>
      <master startport='2'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x1'/>
    </controller>
    <controller type='usb' index='0' model='ich9-uhci3'>
      <master startport='4'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x2'/>
    </controller>
    <controller type='pci' index='0' model='pci-root'/>
    <controller type='virtio-serial' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>
    </controller>
    <interface type='network'>
      <source network='private'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <serial type='pty'>
      <target type='isa-serial' port='0'>
        <model name='isa-serial'/>
      </target>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
      <address type='virtio-serial' controller='0' bus='0' port='1'/>
    </channel>
    <channel type='spicevmc'>
      <target type='virtio' name='com.redhat.spice.0'/>
      <address type='virtio-serial' controller='0' bus='0' port='2'/>
    </channel>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <graphics type='spice' autoport='yes'>
      <listen type='address'/>
      <image compression='off'/>
    </graphics>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x0'/>
    </memballoon>
    <rng model='virtio'>
      <backend model='random'>/dev/urandom</backend>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x0'/>
    </rng>
  </devices>
</domain>
ENDXML
	virsh define $F
	R=$?
	rm $F
	return $R
}
