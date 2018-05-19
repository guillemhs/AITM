#!/bin/bash
set -eux

config_fqdn=$(hostname --fqdn)


#
# configure apt.

echo 'Defaults env_keep += "DEBIAN_FRONTEND"' >/etc/sudoers.d/env_keep_apt
chmod 440 /etc/sudoers.d/env_keep_apt
export DEBIAN_FRONTEND=noninteractive

apt-get update

rm /var/lib/dpkg/lock
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
# provision vim.

apt-get install -y --no-install-recommends vim

cat>~/.vimrc<<'EOF'
syntax on
set background=dark
set esckeys
set ruler
set laststatus=2
set nobackup
EOF


#
# configure the shell.

cat>~/.bash_history<<'EOF'
vim /opt/sonarqube/conf/sonar.properties
systemctl stop sonarqube
systemctl restart sonarqube
journalctl -u sonarqube --follow
tail -f /opt/sonarqube/logs/access.log
tail -f /opt/sonarqube/logs/sonar.log
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
EOF

cat>~/.bashrc<<'EOF'
# If not running interactively, don't do anything
[[ "$-" != *i* ]] && return

export EDITOR=vim
export PAGER=less

alias l='ls -lF --color'
alias ll='l -a'
alias h='history 25'
alias j='jobs -l'
EOF

cat>~/.inputrc<<'EOF'
"\e[A": history-search-backward
"\e[B": history-search-forward
"\eOD": backward-word
"\eOC": forward-word
set show-all-if-ambiguous on
set completion-ignore-case on
EOF


#
# create a self-signed certificate.

pushd /etc/ssl/private
openssl genrsa \
    -out $config_fqdn-keypair.pem \
    2048 \
    2>/dev/null
chmod 400 $config_fqdn-keypair.pem
openssl req -new \
    -sha256 \
    -subj "/CN=$config_fqdn" \
    -key $config_fqdn-keypair.pem \
    -out $config_fqdn-csr.pem
openssl x509 -req -sha256 \
    -signkey $config_fqdn-keypair.pem \
    -extensions a \
    -extfile <(echo "[a]
        subjectAltName=DNS:$config_fqdn
        extendedKeyUsage=serverAuth
        ") \
    -days 365 \
    -in  $config_fqdn-csr.pem \
    -out $config_fqdn-crt.pem
popd


#
# setup nginx proxy to SonarQube that is running at localhost:9000.

apt-get install -y --no-install-recommends nginx
cat<<EOF>/etc/nginx/sites-available/sonarqube
ssl_session_cache shared:SSL:4m;
ssl_session_timeout 6h;
#ssl_stapling on;
#ssl_stapling_verify on;
server {
    listen 80;
    server_name $config_fqdn;
    ssl_certificate /etc/ssl/private/$config_fqdn-crt.pem;
    ssl_certificate_key /etc/ssl/private/$config_fqdn-keypair.pem;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    # see https://github.com/cloudflare/sslconfig/blob/master/conf
    # see https://blog.cloudflare.com/it-takes-two-to-chacha-poly/
    # see https://blog.cloudflare.com/do-the-chacha-better-mobile-performance-with-cryptography/
    # NB even though we have CHACHA20 here, the OpenSSL library that ships with Ubuntu 16.04 does not have it. so this is a nop. no problema.
    ssl_ciphers EECDH+CHACHA20:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:EECDH+3DES:RSA+3DES:!aNULL:!MD5;
    add_header Strict-Transport-Security "max-age=31536000; includeSubdomains";
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    client_max_body_size 50m;
    location = /favicon.ico {
        return 204;
        access_log off;
        log_not_found off;
    }
    location / {
        root /opt/sonarqube/web;
        try_files \$uri @sonarqube;
    }
    location @sonarqube {
        proxy_pass http://localhost:9000;
        proxy_redirect http://localhost:9000/ /;    # needed for the SonarQube Runners to push the report to this SonarQube instance.
        proxy_redirect https://localhost:9000/ /;   # needed for the SonarQube Web Application links.
    }
}
EOF
rm -rf /etc/nginx/sites-enabled/
mkdir /etc/nginx/sites-enabled/
ln -s ../sites-available/sonarqube /etc/nginx/sites-enabled/sonarqube
systemctl restart nginx


#
# install postgres.

apt-get install -y --no-install-recommends postgresql

# create user and database.
postgres_sonarqube_password=$(openssl rand -hex 32)
sudo -sHu postgres psql -c "create role sonarqube login password '$postgres_sonarqube_password'"
sudo -sHu postgres createdb -E UTF8 -O sonarqube sonarqube


#
# install SonarQube.

# install dependencies.
apt-get install -y default-jre
apt-get install -y unzip
apt-get install -y dos2unix

# add the sonarqube user.
groupadd --system sonarqube
adduser \
    --system \
    --disabled-login \
    --no-create-home \
    --gecos '' \
    --ingroup sonarqube \
    --home /opt/sonarqube \
    sonarqube
install -d -o root -g sonarqube -m 751 /opt/sonarqube

# import sonarqube key. gpg --list-keys --fingerprint should output:
#   pub   2048R/D26468DE 2015-05-25
#         Key fingerprint = F118 2E81 C792 9289 21DB  CAB4 CFCA 4A29 D264 68DE
#   uid                  sonarsource_deployer (Sonarsource Deployer) <infra@sonarsource.com>
#   sub   2048R/06855C1D 2015-05-25
gpg --keyserver ha.pool.sks-keyservers.net --recv-keys F1182E81C792928921DBCAB4CFCA4A29D26468DE

# download and install SonarQube.
pushd /opt/sonarqube
sonarqube_version=6.7
sonarqube_directory_name=sonarqube-$sonarqube_version
sonarqube_artifact=$sonarqube_directory_name.zip
sonarqube_download_url=https://sonarsource.bintray.com/Distribution/sonarqube/$sonarqube_artifact
sonarqube_download_sig_url=$sonarqube_download_url.asc
wget -q $sonarqube_download_url
wget -q $sonarqube_download_sig_url
gpg --batch --verify $sonarqube_artifact.asc $sonarqube_artifact
unzip -q $sonarqube_artifact
mv $sonarqube_directory_name/* .
rm -rf $sonarqube_directory_name bin $sonarqube_artifact*
for d in data logs temp extensions; do
    chmod 700 $d
    chown -R sonarqube:sonarqube $d
done
chown -R root:sonarqube conf
chmod 750 conf
chmod 640 conf/*
dos2unix conf/*
popd

# configure it to use PostgreSQL
sed -i -E 's,^#?(sonar.jdbc.username=).*,\1sonarqube,' /opt/sonarqube/conf/sonar.properties
sed -i -E "s,^#?(sonar.jdbc.password=).*,\1$postgres_sonarqube_password," /opt/sonarqube/conf/sonar.properties
sed -i -E 's,^#?(sonar.jdbc.url=jdbc:postgresql://).*,\1localhost/sonarqube,' /opt/sonarqube/conf/sonar.properties
# configure it to only listen at localhost (nginx will proxy to it).
sed -i -E 's,^#?(sonar.web.host=).*,\1127.0.0.1,' /opt/sonarqube/conf/sonar.properties

# start it.
cat >/etc/systemd/system/sonarqube.service <<EOF
[Unit]
Description=sonarqube
After=network.target

[Service]
Type=simple
User=sonarqube
Group=sonarqube
WorkingDirectory=/opt/sonarqube
ExecStart=/usr/bin/java \
    -jar /opt/sonarqube/lib/sonar-application-$sonarqube_version.jar \
    -Dsonar.log.console=true
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable sonarqube
systemctl start sonarqube

# wait for it to come up.
apt-get install -y --no-install-recommends curl
apt-get install -y --no-install-recommends jq
function wait_for_ready {
    sleep 5
    bash -c 'while [[ "$(curl -s localhost:9000/api/system/status | jq --raw-output ''.status'')" != "UP" ]]; do sleep 5; done'
}
wait_for_ready

# list out-of-box installed plugins. at the time of writing they were:
#   csharp
#   flex
#   java
#   javascript
#   php
#   python
#   scmgit
#   scmsvn
#   typescript
#   xml
curl -s -u admin:admin localhost:9000/api/plugins/installed \
    | jq --raw-output '.plugins[].key' \
    | sort \
    | xargs -n 1 -I % echo 'out-of-box installed plugin: %'

# update the existing plugins.
curl -s -u admin:admin localhost:9000/api/plugins/updates \
    | jq --raw-output '.plugins[].key' \
    | xargs -n 1 -I % curl -s -u admin:admin -X POST localhost:9000/api/plugins/update -d 'key=%'

# install new plugins.
plugins=(
    'ldap'            # https://docs.sonarqube.org/display/PLUG/LDAP+Plugin
    'checkstyle'      # https://github.com/checkstyle/sonar-checkstyle
)
for plugin in "${plugins[@]}"; do
    echo "installing the $plugin plugin..."
    curl -s -u admin:admin -X POST localhost:9000/api/plugins/install -d "key=$plugin"
done
echo 'restarting SonarQube...'
curl -s -u admin:admin -X POST localhost:9000/api/system/restart
wait_for_ready


#
# build some Java projects and send them to SonarQube.
# see https://docs.sonarqube.org/display/SCAN/Analyzing+with+SonarQube+Scanner

apt-get install -y --no-install-recommends git-core
apt-get install -y --no-install-recommends default-jdk
apt-get install -y --no-install-recommends maven
