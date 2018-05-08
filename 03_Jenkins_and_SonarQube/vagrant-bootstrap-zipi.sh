#!/usr/bin/env bash

########################### JENKINS SERVER ###########################

wget -q -O - https://pkg.jenkins.io/debian/jenkins-ci.org.key | sudo apt-key add -
sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'

apt-get update

apt-get -y install jenkins
systemctl start jenkins

apt-get -y install openjdk-8-jre openjdk-8-jdk



echo "Jenkins admin password: "
cat /var/lib/jenkins/secrets/initialAdminPassword
