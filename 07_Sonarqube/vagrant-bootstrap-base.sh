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
        software-properties-common \
        docker-ce

# install docker-compose
curl -L "https://github.com/docker/compose/releases/download/1.19.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose

# install docker-machine
curl -L "https://github.com/docker/machine/releases/download/v0.13.0/docker-machine-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-machine && \
    chmod +x /usr/local/bin/docker-machine

reboot
