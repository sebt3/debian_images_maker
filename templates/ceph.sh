#!/bin/bash
#@DESC@ A docker VM using the docker official repo
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

ceph.install.verify() { task.verify.rc; }
ceph.install() {
	if [[ "$ARCH" = "amd64" ]];then
		echo "deb http://eu.ceph.com/debian-luminous/ xenial main" >"$OSROOT/etc/apt/sources.list.d/ceph.list"
		curl -s "https://git.ceph.com/?p=ceph.git;a=blob_plain;f=keys/release.asc" | apt.key
	else
		echo "deb http://sebt3.github.io/packages stretch main" >"$OSROOT/etc/apt/sources.list.d/ceph.list"
		curl -s "https://sebt3.github.io/packages/PUBLIC.KEY" | apt.key
		apt.install apt-transport-https
	fi
	image.chroot apt-get update
	mkdir -p "$OSROOT/run/uuidd"
	#LANG=C chroot "$MP" systemctl unmask lvm2-lvmetad.socket lvm2-lvmpolld.socket
	apt.install rbd-nbd ceph-mds ceph-osd ceph-mon ceph-mgr python-pip
}
ceph.tasks() {
	task.add ceph.install	"Install ceph"
}
TEMPLATES+=(ceph.tasks)
