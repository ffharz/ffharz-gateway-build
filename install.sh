#!/bin/bash

## Dieses Script richtet einen Freifunk Harz Gateway automatisiert ein
## Voraussetzung ist ein "jungfreuliches" Debian 10 Buster

# Software-Update und notwendige Pakete installieren
apt update
apt upgrade
apt install batctl fastd bridge-utils

# Config laden

declare -A config
INPUT=gateways.csv
OLDIFS=$IFS
IFS=';'
[ ! -f $INPUT ] && { echo "$INPUT Datei nicht gefunden!"; exit 99; }
while read domain nr name dns host ip fastdport fastdbbport bbmac v4mac v6mac dhcprange dhcpstart dhcpend fastdbbsec fastdbbpub fastdsec fastdpub
do
    if [ "$HOSTNAME" == "$name" ]; then
        config[domain]=$domain
        config[nr]=$nr
        config[name]=$name
        config[dns]=$dns
        config[host]=$host
        config[ip]=$ip
        config[fastdport]=$fastdport
        config[fastdbbport]=$fastdbbport
        config[bbmac]=$bbmac
        config[v4mac]=$v4mac
        config[v6mac]=$v6mac
        config[dhcprange]=$dhcprange
        config[dhcpstart]=$dhcpstart
        config[dhcpend]=$dhcpend
        config[fastdbbsec]=$fastdbbsec
        config[fastdbbpub]=$fastdbbpub
        config[fastdsec]=$fastdsec
        config[fastdpub]=$fastdpub

    fi

done < $INPUT
IFS=$OLDIFS

# batman-adv Kernel-Modul aktivieren (nach Neustart)
echo "batman-adv" >> /etc/modules

# batman-adv Kernel-Modul sofort laden
modprobe batman-adv

# fastd Config kopieren

cp fastd/. /etc/fastd/ -r

# FastD-Config anpassen
sed -i "s/10000/${config[fastdbbport]}/g" /etc/fastd/backbone/fastd.conf
# sed -i "s/0.0.0.0/${config[ip]}/g" /etc/fastd/backbone/fastd.conf
sed -i "s/00:00:00:00:00:00/${config[bbmac]}/g" /etc/fastd/backbone/fastd.conf

sed -i "s/10000/${config[fastdport]}/g" /etc/fastd/v4/fastd.conf
# sed -i "s/0.0.0.0/${config[ip]}/g" /etc/fastd/v4/fastd.conf
sed -i "s/00:00:00:00:00:00/${config[v4mac]}/g" /etc/fastd/v4/fastd.conf

sed -i "s/10000/${config[fastdport]}/g" /etc/fastd/v6/fastd.conf
# sed -i "s/0.0.0.0/${config[ip]}/g" /etc/fastd/v6/fastd.conf
sed -i "s/00:00:00:00:00:00/${config[v6mac]}/g" /etc/fastd/v6/fastd.conf

# FastD Secrets ablegen
echo "secret \"${config[fastdbbsec]}\";" > /etc/fastd/backbone/secret.conf
echo "secret \"${config[fastdsec]}\";" > /etc/fastd/v4/secret.conf
echo "secret \"${config[fastdsec]}\";" > /etc/fastd/v6/secret.conf