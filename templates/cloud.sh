#!/bin/bash
#@DESC@ Infra node
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

K8S_LOAD_CUSTOM=no templates.load k8s
templates.load etcd
templates.load pacemaker
templates.load ceph
OSSIZE=${OSSIZE:-"3G"}
DIST=testing

##############################################################################
### Create Tasks
##

registry.install() {
	apt.install docker-registry
}

conf.cni() {
	mkdir -p "$OSROOT/etc/cni/net.d" "$OSROOT/var/log/journal"  "$OSROOT/var/run/flannel"

	cat >"$OSROOT/etc/cni/net.d/10-weave.conf" <<ENDCFG
{
    "name": "weave",
    "type": "weave-net",
    "hairpinMode": true
}
ENDCFG
}
conf.kubelet.verify() { task.verify.permissive; }
conf.kubelet() {
	mkdir -p "$OSROOT/etc/systemd/system/kubelet.service.d/" "$OSROOT/etc/cni/net.d" "$OSROOT/var/log/journal" "$OSROOT/etc/kubernetes/manifests"
	image.chroot systemctl enable kubelet
}

infra.tasks() {
	task.add 		registry.install	"Install the docker registry"
	task.add 		conf.kubelet		"Configure kubelet"
	task.add 		conf.cni		"Configure the cni"
}
TEMPLATES+=(infra.tasks)

