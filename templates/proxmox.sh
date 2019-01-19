#!/bin/bash
#@DESC@A proxmox instance
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


DIST=stretch
SVLAN=${SVLAN:-"10.0.1"}
args.declare SVLAN   -S --sec-vlan  Vals NoOption NotMandatory "Secondary VLAN 		(DEFAULT: $SVLAN)"

NODES=( prox1 prox2 )

proxmox.base.verify() { task.verify.rc; }
proxmox.base() {
	apt.install ca-certificates gnupg2 ebtables ethtool postfix glusterfs-server xfsprogs
}

proxmox.setup() {
	# voir: https://pve.proxmox.com/wiki/Network_Configuration
	# en physique faire plutot du bridge plus classique (sans les pre-up et avec bridge_ports positionné à la carte phisique a bridger: ici ens3)
	cat >"$OSROOT/etc/network/interfaces.d/vmbr0"<<END
auto vmbr0
iface vmbr0 inet static
        address  ${SVLAN}.$LIP
        netmask  255.255.255.0
        bridge_ports none
        bridge_stp off
        bridge_fd 0

        pre-up echo 1 > /proc/sys/net/ipv4/ip_forward
        pre-up echo 1 > /proc/sys/net/ipv4/conf/ens3/proxy_arp
END
}
proxmox.install.verify() { task.verify.rc; }
proxmox.install() {
	local R=0
	echo "deb http://download.proxmox.com/debian/pve stretch pve-no-subscription" > "$OSROOT/etc/apt/sources.list.d/pve-install-repo.list"
	sed -i 's/main.*/main contrib/' "$OSROOT/etc/apt/sources.list"
	echo "deb http://security.debian.org stretch/updates main contrib">"$OSROOT/etc/apt/sources.list.d/security.list"
	curl -s http://download.proxmox.com/debian/proxmox-ve-release-5.x.gpg | apt.key
	image.chroot apt-get update
	image.chroot apt remove -y os-prober
	apt.install proxmox-ve open-iscsi #pve-headers-4.15.18-9-pve
	R=$?
	>"$OSROOT/etc/apt/sources.list.d/pve-enterprise.list"
	return $R
}

proxmox.tasks() {
	task.add proxmox.base 		"Download base packages for proxmox"
	task.add proxmox.setup 		"Configure the vlan for VMs"
	task.add proxmox.install	"install proxmox"
}
TEMPLATES+=(proxmox.tasks)


##############################################################################
### Post install stuff : 
##	Configure the cluster

key.init.verify() { task.verify.permissive; }
key.init() {
	local i j
	local AUTH=$(for ((i=0;$i<${#NODES[@]};i++));do net.run "${NODES[$i]}" "cat /etc/pve/priv/authorized_keys";done|sort -u)
	for ((i=0;$i<${#NODES[@]};i++));do
		echo "$AUTH"|net.file "${NODES[$i]}" "/etc/pve/priv/authorized_keys"
	done
	for ((i=0;$i<${#NODES[@]};i++));do
		for ((j=0;$j<${#NODES[@]};j++));do
			net.run "${NODES[$i]}" "ssh -oStrictHostKeyChecking=no ${NODES[$j]} true"
		done
	done
	
}

gluster.vg() {
	pvcreate /dev/vdb
	vgcreate gluster /dev/vdb
}
gluster.stop() {
	systemctl stop glusterfs-server
}
gluster.lv_lib() {
	lvcreate -L 5G -n lib gluster
	mkfs.ext4 /dev/gluster/lib
	rm -rf /var/lib/glusterd
	mkdir /var/lib/glusterd
	mount /dev/gluster/lib /var/lib/glusterd
	grep /var/lib/glusterd /etc/mtab >>/etc/fstab
}	
gluster.start() {
	systemctl start glusterfs-server
}
gluster.brick1() {
	lvcreate -n data -l 100%FREE gluster
	mkfs.xfs /dev/gluster/data
	mkdir -p /data/brick1
	mount /dev/gluster/data /data/brick1
	grep /dev/gluster/data /etc/mtab >>/etc/fstab
	mkdir -p /data/brick1/vol1
}

gluster.peers() {
	for ((i=1;$i<${#NODES[@]};i++));do
		net.run "${NODES[0]}" "gluster peer probe ${NODES[$i]}"
	done
}
gluster.volume1() {
	local max=3 cmd="" i
	[ $max -gt ${#NODES[@]} ] && max=${#NODES[@]}
	for ((i=0;$i<$max;i++));do
		cmd="$cmd ${NODES[$i]}:/data/brick1/vol1"
	done
	net.run "${NODES[0]}" "gluster volume create vol1 replica $max $cmd"
	net.run "${NODES[0]}" "gluster volume start vol1"
}


cluster.create() {
	pvecm create cluster
}

cluster.add() {
	local ip=$(net.run "${NODES[0]}" "hostname -i")
	net.run "$1"  "pvecm add $ip -use_ssh"
}

lxc.repo.update() {
	pveam update
}


cluster() {
	local i
	task.add 			key.init	"Exchange ssh keys"
	for ((i=0;$i<${#NODES[@]};i++));do
		task.add "${NODES[$i]}"	gluster.vg	"Create the volum group for gluster on ${NODES[$i]}"
		task.add "${NODES[$i]}"	gluster.stop	"Stop gluster on ${NODES[$i]}"
		task.add "${NODES[$i]}"	gluster.lv_lib	"Create lib FS for gluster on ${NODES[$i]}"
		task.add "${NODES[$i]}"	gluster.start	"Start gluster on its lib FS on ${NODES[$i]}"
		task.add "${NODES[$i]}"	gluster.brick1	"Create the brick on ${NODES[$i]}"
	done
	task.add 			gluster.peers	"Connected all peers from ${NODES[0]}"
	task.add 			gluster.volume1	"Create the initial volume"

	task.add "${NODES[0]}"		cluster.create	"Create the cluster"
	for ((i=1;$i<${#NODES[@]};i++));do
		eval "cluster.add.${NODES[$i]}() { cluster.add \"${NODES[$i]}\"; }"
		task.add 		"cluster.add.${NODES[$i]}" "Add ${NODES[$i]} to the cluster"
	done
	if [ ${#NODES[@]} -eq 2 ];then
		: #TODO: Should create some fencing
	fi
	for ((i=0;$i<${#NODES[@]};i++));do
		task.add "${NODES[$i]}"	lxc.repo.update	"update the lxc template list on ${NODES[$i]}"
	done

}
act.add.post cluster "Setup the proxmox cluster"
