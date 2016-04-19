#!/bin/bash

# file    : lxc-alpine-container.sh
# purpose : this script will create a new alpine container that is ready for ansible management
# requires: ssh-config
#
# author  : harald van der laan
# version : v1.0
# date    : 2016/04/19

lxcContainerName=${1}
lxcAnsibleContainer=${2}
lxcInstallYes="[yY][eE][sS]"

if [ -z ${2} ]; then
	echo "[-]: usage: ${0} <lxc container name> <ansible container>"
	exit 1
fi

# check if lxc is installed
if [ -z $(which lxc) ]; then
	read -ep "[-]: lxc is not installed, would you like to install it (yes/no): " -i "yes" lxcInstall
	
	# check if this script needs to install lxc
	if [[ ${lxcInstall} =~ ${lxcInstallYes} ]]; then
		# check if user is root or regular user
		if [ ${UID} -eq 0 ]; then
			apt-add-repository ppa:ubuntu-lxc/lxd-stable
			apt-get update
			apt-get install lxd
		else
			sudo apt-add-repository ppa:ubuntu-lxc/lxd-stable
			sudo apt-get update
			sudo apt-get install lxd
		fi
	else
		exit 1
	fi
fi

# check if lxc container name is provided
if [ -z ${lxcContainerName} ]; then
	read -ep "[-]: please enter the ansible container name: " -i "lxc-server01" lxcContainerName
fi

lxcAlpineImage=$(lxc image list | egrep "^\|\ alpine\ " &> /dev/null; echo ${?})
lxcContainerExists=$(lxc list | egrep "^\|\ ${lxcContainerName}\ " &> /dev/null; echo ${?})
lxcAnsibleContainerExists=$(lxc list | egrep "^\|\ ${lxcAnsibleContainer}\ " &> /dev/null; echo ${?})

# the ansible management server will be based on alpine linux 3.3 (amd64)
# this check will look for the alpine image local
if [ ${lxcAlpineImage} -ne 0 ]; then
	# alpine linux 3.3 image is not local
	echo "[ ]: downloading alpine linux 3.3 lxc image"
	lxc image copy images:alpine/3.3/amd64 local: --alias=alpine &> /dev/null && \ 
		echo "[+]: alpine linux 3.3 lxc image downloaded"
fi

# check if there is no container running with the same name
if [ ${lxcContainerExists} -eq 0 ]; then
	echo "[-]: there is a container running with the name: ${lxcContainerName}"
	exit 1
fi

# main script
echo "[ ]: starting clean alpine linux 3.3"
lxc launch alpine ${lxcContainerName} &> /dev/null && \
	echo "[+]: clean alpine linux 3.3 started"

echo "[ ]: update alpine linux 3.3 to latest patch level"
lxc exec ${lxcContainerName} -- apk --update-cache upgrade &> /dev/null && \
	echo "[+]: alpine linux 3.3 up to latest patch level"

echo "[ ]: installing requirements (this could take some time)"
lxc exec ${lxcContainerName} -- apk add bash bash-completion python openssh &> /dev/null && \
	echo "[+]: requirements are installed"

echo "[ ]: configurating openssh"
lxc exec ${lxcContainerName} -- rc-update add sshd &> /dev/null
lxc exec ${lxcContainerName} -- /etc/init.d/sshd start &> /dev/null
lxc exec ${lxcContainerName} -- mkdir -p /root/.ssh
if [ ${lxcAnsibleContainerExists} -eq 0 ]; then
	lxc file pull ${lxcAnsibleContainer}/root/.ssh/id_rsa.pub a
	cat a > authorized_keys
        if [ ! -f ~/.ssh/id_rsa.pub ]; then
        	echo "[ ]: creating public and private key pair"
        	ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N ""
	fi
	cat ~/.ssh/id_rsa.pub >> authorized_keys
	lxc file push authorized_keys ${lxcContainerName}/root/.ssh/authorized_keys --uid=0 --gid=0 --mode=0644
	rm a authorized_keys
else
	echo "[-]: could not find the ansible server: ${lxcAnsibleContainer}"
fi

echo "[+]: openssh is configured"

echo "[ ]: correcting system configuration"
lxc exec ${lxcContainerName} -- sed -i 's/\/bin\/ash/\/bin\/bash/g' /etc/passwd 

echo "[!]: container ${lxcContainerName} is ready for use"
echo
exit 0