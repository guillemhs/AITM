#!/usr/bin/env bash

########################### JENKINS NODE ###########################

# upgrading system
apt-get update
sudo dpkg --configure -a
apt-get -y upgrade

# language settings
apt-get -y install language-pack-en
locale-gen en_GB.UTF-8
sudo dpkg --configure -a

# install openjdk
apt-get -y install openjdk-8-jre openjdk-8-jdk
