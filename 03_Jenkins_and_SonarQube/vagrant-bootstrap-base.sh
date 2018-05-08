#!/bin/bash
rm /var/lib/dpkg/lock
rm /var/lib/apt/lists/lock
rm /var/cache/apt/archives/lock
apt-get update
dpkg --configure -a
apt-get -y upgrade
dpkg --configure -a

apt-get install -y --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        curl \
        software-properties-common \
        python-minimal zip python-simplejson \
        gnupg2 \
        software-properties-common

apt-get remove docker docker-engine docker.io

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

apt-key fingerprint 0EBFCD88

add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

apt-get update

apt-get install docker-ce -y

# install docker-compose
curl -L "https://github.com/docker/compose/releases/download/1.19.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose

# install docker-machine
curl -L "https://github.com/docker/machine/releases/download/v0.13.0/docker-machine-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-machine && \
    chmod +x /usr/local/bin/docker-machine

apt-get -y upgrade
apt-get -y dist-upgrade

reboot
