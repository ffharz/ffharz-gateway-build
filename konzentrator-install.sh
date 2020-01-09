#!/bin/bash

## Dieses Script richtet einen Freifunk Harz Konzentrator auf einem Hetzner Cloud Server automatisiert ein
## Voraussetzung ist ein "jungfreuliches" Debian 10 Buster

if [ -d "config/" ] ; then 
    read -p"Config-Verzeichnis vorhanden, soll trotzdem weiter gemacht werden? (wird gelöscht!) (j/n) " force
    if [ "$force" != "j" ] ; then
        exit 1
    fi
fi

fullrun=true
read -p"Soll nur das Config-Verzeichnis aufgebaut werden, ohne das Systemdatei geändert werden? (j/n) " response
if [ "$response" != "n" ] ; then
    fullrun=false
fi

echo "- Start"

## Config laden
echo "- Konzentrator-Konfiguration aus hc-gateways.csv laden"
declare -A config
INPUT=hc-gateways.csv
OLDIFS=$IFS
IFS=';'
[ ! -f $INPUT ] && { echo "$INPUT Datei nicht gefunden!"; exit 99; }
while read domain nr name dns host ip ffip ipv6 ipv6gw ffipv6 bbmac v4mac v6mac dhcprange dhcpstart dhcpend fastdbbsec fastdbbpub fastdsec fastdpub
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

if [[ ! -v "config[name]" ]] ; then
    echo "Der Hostname $HOSTNAME wurde nicht in der hc-gateways.csv gefunden! Hat das Gateway den richtigen Hostname und besteht eine Konfiguration in der csv? Abbruch..."
    exit 99
fi

## Konfiguration anlegen

if [ -d "config/" ] ; then 
    echo "- altes Konfigurationsverzeichnis löschen"
    rm config -r -d
fi

echo "- Konfigurationsverzeichniss anlegen und Templates kopieren"
mkdir config/
cp template/. config/ -r
mkdir config/fastd/backbone/gateway/


## fastd Config
echo "- Konfigurationsdateien für fastd anpassen"

## FastD-Config anpassen
sed -i "s/0.0.0.0/192.168.1.${config[nr]}/g" config/fastd/backbone/fastd.conf
sed -i "s/00:00:00:00:00:00/${config[bbmac]}/g" config/fastd/backbone/fastd.conf

## FastD Secret ablegen
echo "- fastd secret hinterlegen"
echo "secret \"${config[fastdbbsec]}\";" > config/fastd/backbone/secret.conf


## DNS Server Liste erstellen und Public-Key von Konzentrator hinterlegen
echo "- fastd public-Keys der Gateways in der Domäne anlegen "

OLDIFS=$IFS
IFS=';'
[ ! -f $INPUT ] && { echo "$INPUT Datei nicht gefunden!"; exit 99; }
while read domain nr name dns host ip ffip ipv6 ipv6gw ffipv6 bbmac v4mac v6mac dhcprange dhcpstart dhcpend fastdbbsec fastdbbpub fastdsec fastdpub
do
    if [ "${config[domain]}" == "$domain" ] && [ "$HOSTNAME" != "$name" ]; then
        echo "key \"$fastdbbpub\";" > config/fastd/backbone/gateway/$name
        echo "remote \"192.168.1.$nr\" port 10001;" >> config/fastd/backbone/gateway/$name
    fi

done < $INPUT
IFS=$OLDIFS

## IPv6 und Netzwerkbridge in interfaces anpassen
echo "- Netzwerkkonfiguration vorbereiten (IPv6, br-ffharz)"
sed -i "s/<ffipv6>/${config[ffipv6]}/g" config/99-ff-bridge.cfg
sed -i "s/<ipv6gw-1>/${config[ipv6gw]::-1}/g" config/99-ff-bridge.cfg
sed -i "s/<ffip>/${config[ffip]}/g" config/99-ff-bridge.cfg
sed -i "s/pre-up batctl gw server/#pre-up batctl gw server/g" config/99-ff-bridge.cfg
sed -i "s/post-up batctl gw server 1000MBit\/1000MBit/#post-up batctl gw server 1000MBit\/1000MBit/g" config/99-ff-bridge.cfg

##respondd Konfiguration anpassen
echo "- respondd Konfiguration anpassen"
sed -i "s/<name>/${config[name]}/g" config/respondd.config.json
sed -i "s/<bbmac>/${config[bbmac]}/g" config/respondd.config.json
## ToDo: Firmware/batman-adv Version in Konfig schreiben

if $fullrun; then 

    ## Paketequellen aktualisieren und Pakete installieren
    echo "- Paketquellen aktualisieren und notwendige Pakete installieren (batctl fastd bridge-utils python3-netifaces nftables )"
    apt update
    apt upgrade
    apt install batctl fastd bridge-utils python3-netifaces nftables 

    echo "- batman-adv Kernelmodul Autostart aktivieren und sofort laden"
    ## batman-adv Kernel-Modul aktivieren (nach Neustart)
    echo "batman-adv" >> /etc/modules
    ## batman-adv Kernel-Modul sofort laden
    modprobe batman-adv

    ## Konfigurationsdateien an richtige Stelle kopieren
    echo "- fastd Konfigurationsdateien nach /etc/fastd kopieren"
    cp config/fastd/. /etc/fastd/ -r
    rm -r -d /etc/fastd/v4
    rm -r -d /etc/fastd/v6

    ## FastD Autostart einrichten
    echo "- fastd Autostart einrichten"
    cp config/fastd@.service /etc/systemd/system/fastd@.service
    systemctl daemon-reload
    systemctl enable fastd@backbone

    echo "- Netzwerk Konfiguration nach /etc/network/interfaces.d/99-ff-bridge.cfg kopieren"
    cat config/99-ff-bridge.cfg > /etc/network/interfaces.d/99-ff-bridge.cfg

   ## respondd installieren
    echo "- respondd installieren, konfigurieren und Autostart einrichten"
    git clone https://github.com/FreifunkHochstift/ffho-respondd.git /opt/ext-respondd
    cp config/respondd.config.json /opt/ext-respondd/config.json

    cp /opt/ext-respondd/ext-respondd.service.example /lib/systemd/system/ext-respondd.service
    #sed -i "s/\/opt\/ext-respondd/\/opt\/respondd/g" /lib/systemd/system/respondd.service
    systemctl daemon-reload
    systemctl enable ext-respondd

    ## Firewall-Regeln laden

    echo "- Verzeichnis /etc/nftables/ anlegen und Ruleset dort ablegen"
    
    if [ ! -d "/etc/nftables" ] ; then 
        mkdir /etc/nftables/
        echo "include \"/etc/nftables/*.nft\"" >> /etc/nftables.conf
    fi

    cp config/konzentrator-firewall.nft /etc/nftables/konzentrator-firewall.nft

    echo "- nftable Firewall Autostart einrichten"
    systemctl enable nftables.service
    

    ## SSH-zugang auf Port 65333 legen
    echo "- SSH Port auf 65333 legen"
    sed -i "s/#Port 22/Port 65333/g" /etc/ssh/sshd_config

    ## IP Forwarding aktivieren
    echo "- IPForwarding aktivieren"
    sed -i "s/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g" /etc/sysctl.conf
    sed -i "s/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/g" /etc/sysctl.conf


    ## Ende
    echo "Fertig! --> reboot"
fi