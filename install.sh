#!/bin/bash

## Dieses Script richtet einen Freifunk Harz Gateway automatisiert ein
## Voraussetzung ist ein "jungfreuliches" Debian 10 Buster

# Software-Update und notwendige Pakete installieren
apt update
apt upgrade
apt install batctl fastd bridge-utils isc-dhcp-server radvd iptables-persistent dnsmasq

# Config laden

declare -A config
INPUT=gateways.csv
OLDIFS=$IFS
IFS=';'
[ ! -f $INPUT ] && { echo "$INPUT Datei nicht gefunden!"; exit 99; }
while read domain nr name dns host ip ffip ipv6 ipv6gw ffipv6 fastdport fastdbbport bbmac v4mac v6mac dhcprange dhcpstart dhcpend fastdbbsec fastdbbpub fastdsec fastdpub
do
    if [ "$HOSTNAME" == "$name" ]; then
        config[domain]=$domain
        config[nr]=$nr
        config[name]=$name
        config[dns]=$dns
        config[host]=$host
        config[ip]=$ip
        config[ffip]=$ffip
        config[ipv6]=$ipv6
        config[ipv6gw]=$ipv6gw
        config[ffipv6]=$ffipv6    
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

# Public-Keys der Gateways der gleichen Domäne hinterlegen

mkdir /etc/fastd/backbone/gateway

OLDIFS=$IFS
IFS=';'
[ ! -f $INPUT ] && { echo "$INPUT Datei nicht gefunden!"; exit 99; }
while read domain nr name dns host ip fastdport fastdbbport bbmac v4mac v6mac dhcprange dhcpstart dhcpend fastdbbsec fastdbbpub fastdsec fastdpub
do
    if [ "${config[domain]}" == "$domain" ] && [ "$HOSTNAME" != "$name" ]; then
        echo "key \"$fastdbbpub\";" > /etc/fastd/backbone/gateway/$name
        echo "remote \"$dns\" port $fastdbbport;" >> /etc/fastd/backbone/gateway/$name
    fi

done < $INPUT
IFS=$OLDIFS

# FastD Autostart einrichten
cp fastd@.service /etc/systemd/system/fastd@.service
systemctl daemon-reload
systemctl enable fastd@backbone
systemctl enable fastd@v4
systemctl enable fastd@v6

# IPv6 und Netzwerkbridge einrichten
echo "

iface ens18 inet6 static
  address ${config[ipv6]}
  netmask 64
  gateway ${config[ipv6gw]}

auto br-ffharz
iface br-ffharz inet6 static
    bridge-ports none
    address ${config[ffipv6]}
    netmask 48
 
    post-up ip addr add ${config[ipv6]}/64 dev br-ffharz
    post-up ip route add ${config[ipv6gw]::-1}/64 dev br-ffharz
    pre-down ip addr del ${config[ipv6]}/64 dev br-ffharz
    pre-down ip route del ${config[ipv6gw]::-1}/64 dev br-ffharz
 
iface br-ffharz inet static
    address ${config[ffip]}
    netmask 255.255.0.0
 
allow-hotplug bat0
iface bat0 inet6 manual
    pre-up modprobe batman-adv
    pre-up batctl if add mesh-vpn
    pre-up batctl gw server
    up ip link set \$IFACE up
    post-up brctl addif br-ffharz \$IFACE
    post-up batctl it 10000
    post-up batctl gw server 1000MBit/1000MBit
 
    pre-down brctl delif br-ffharz \$IFACE || true
    down ip link set \$IFACE down" >> /etc/network/interfaces