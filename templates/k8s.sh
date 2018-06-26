#!/bin/bash
#@DESC@ A kubernetes node unconfigured using officials repos
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

MASTER=${MASTER:-"kubemaster"}
DOCKER_LOAD_CUSTOM=no templates.load docker

kb.crictl() {
	curl -s -L "https://github.com/kubernetes-incubator/cri-tools/releases/download/v1.0.0-alpha.0/crictl-v1.0.0-alpha.0-linux-${ARCH}.tar.gz" |tar zx -C "$OSROOT/usr/bin"
}
kb.install.verify() { task.verify.permissive; }
kb.install() {
	echo "export KUBECONFIG=/etc/kubernetes/admin.conf">>"$OSROOT/root/.bashrc"
	echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" >"$OSROOT/etc/apt/sources.list.d/kube.list"
	curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt.key
	image.chroot apt-get update
	#apt.install kubectl=1.9.8-00 kubeadm=1.9.8-00 kubelet=1.9.8-00 jq ca-certificates gnupg2 ebtables ethtool uuid-runtime
	apt.install kubectl kubeadm kubelet jq ca-certificates gnupg2 ebtables ethtool
}
kb.bridge() {
	echo "net.bridge.bridge-nf-call-iptables=1
vm.swappiness=0" >"$OSROOT/etc/sysctl.d/bridge.conf"
}

kb.tasks() {
	task.add kb.crictl		"install crictl"
	task.add kb.install		"install kubeadm"
	task.add kb.bridge		"configure the kernel for bridge"
}
TEMPLATES+=(kb.tasks)

############################
####
##  Custom activities
#
if [[ "${K8S_LOAD_CUSTOM:-"yes"}" = "yes" ]];then
setupm.init.verify() { task.verify.permissive; }
setupm.init() {
	# "--apiserver-advertise-address=${VIP}.$LIP"
	net.run "$HNAME" kubeadm init "--pod-network-cidr=10.244.0.0/16" --ignore-preflight-errors=all
}

setupm.enable.verify() { task.verify.permissive; }
setupm.enable() {
	systemctl enable kubelet && systemctl start kubelet
}
setupm.flannel() {
	kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
}
setupmaster() {
	task.add	  setupm.init		"Initialize the kube infrastructure"
	task.add "$HNAME" setupm.enable		"Start the kubelet"
	task.add "$HNAME" setupm.flannel	"Start the flannel"
}
act.add.post setupmaster "Configure a running VM for kubernetes master usage"

setupn.init() {
	local TOKEN=$(net.run "$MASTER" kubeadm token list|awk '/kubeadm/&&/default-node-token/{print $1}')
	local SHA=$(net.run "$MASTER" "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex" | sed 's/^.* //') 
	net.run "$HNAME" kubeadm join --token "$TOKEN" "$MASTER:6443" --discovery-token-ca-cert-hash "sha256:$SHA" --ignore-preflight-errors=all
}
setupnode() {
	task.add setupn.init		"Initialize the kube infrastructure"
}
act.add.post setupnode "Configure a running VM for kubernetes node usage"
fi
