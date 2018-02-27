#!/bin/bash
set -eux

config_fqdn=$(hostname --fqdn)


#
# configure apt.

echo 'Defaults env_keep += "DEBIAN_FRONTEND"' >/etc/sudoers.d/env_keep_apt
chmod 440 /etc/sudoers.d/env_keep_apt
export DEBIAN_FRONTEND=noninteractive
apt-get update


#
# disable IPv6.

cat>/etc/sysctl.d/98-disable-ipv6.conf<<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
systemctl restart procps
sed -i -E 's,(GRUB_CMDLINE_LINUX=.+)",\1 ipv6.disable=1",' /etc/default/grub
update-grub2


#
# configure the firewall.

apt-get install -y iptables
# reset the firewall.
# see https://wiki.archlinux.org/index.php/iptables
for table in raw filter nat mangle; do
    iptables -t $table -F
    iptables -t $table -X
done
for chain in INPUT FORWARD OUTPUT; do
    iptables -P $chain ACCEPT
done
# set the default policy to block incomming traffic.
iptables -P INPUT DROP
iptables -P FORWARD DROP
# allow incomming traffic on the loopback interface.
iptables -A INPUT -i lo -j ACCEPT
# allow incomming established sessions.
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# allow incomming ICMP.
iptables -A INPUT -p icmp --icmp-type any -j ACCEPT
# allow incomming SSH connections.
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
# allow incomming HTTP(S) connections.
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
# load iptables rules on boot.
iptables-save >/etc/iptables-rules-v4.conf
cat>/etc/network/if-pre-up.d/iptables-restore<<'EOF'
#!/bin/sh
iptables-restore </etc/iptables-rules-v4.conf
EOF
chmod +x /etc/network/if-pre-up.d/iptables-restore

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

reboot
