#!/usr/bin/env bash

########################### JENKINS SERVER ###########################

# IMPORTANT: must download "jenkins-nginx" file too
# or "jenkins-apache2"

wget -q -O - https://pkg.jenkins.io/debian/jenkins-ci.org.key | sudo apt-key add -
sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'

apt-get update

# language settings
apt-get -y install language-pack-en
locale-gen en_GB.UTF-8

apt-get -y install git curl vim screen ssh tree lynx links links2 unzip
apt-get -y install openjdk-8-jre openjdk-8-jdk

apt-get -y install jenkins
service jenkins start

echo "Jenkins admin password: "
cat /var/lib/jenkins/secrets/initialAdminPassword
