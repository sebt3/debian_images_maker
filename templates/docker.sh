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

MASTER=${MASTER:-"dockermaster"}
args.declare MASTER   -A --master  Vals NoOption NotMandatory "Master hostname		(DEFAULT: $MASTER)"


docker.base.verify() { task.verify.permissive; }
docker.base() {
	apt.install ca-certificates gnupg2 ebtables ethtool
}
docker.install.verify() { task.verify.permissive; }
docker.install() {
	echo "deb https://download.docker.com/linux/debian buster test" >"$OSROOT/etc/apt/sources.list.d/docker.list"
	curl -s https://download.docker.com/linux/ubuntu/gpg | apt.key
	image.chroot apt-get update
	apt.install docker-ce docker-compose
	image.chroot systemctl enable docker
}
docker.tasks() {
	task.add docker.base 	"Download base packages for docker"
	task.add docker.install	"install docker"
}
TEMPLATES+=(docker.tasks)
############################
####
##  Custom activities
#
if [[ "${DOCKER_LOAD_CUSTOM:-"yes"}" = "yes" ]];then
setupm.init() {
	docker swarm init
}
setupmaster() {
	task.add "$HNAME" setupm.init		"Initialize the swarm"
}
act.add.post setupmaster "Configure a running VM for swarm master usage"

setupb.init() {
	net.run "$HNAME" $(net.run $MASTER docker swarm join-token master|grep join)
}
setupbackup() {
	task.add setupb.init		"Initialize the swarm master backup node"
}
act.add.post setupbackup "Configure a running VM for secondary swarm master"
setupn.init() {
	net.run "$HNAME" $(net.run $MASTER docker swarm join-token worker|grep join)
}
setupnode() {
	task.add setupn.init		"Initialize the swarm node"
}
act.add.post setupnode "Configure a running VM for swarm node usage"
fi
