#!/bin/bash

## Dieses Script richtet einen Freifunk Harz Gateway automatisiert ein
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
echo "- Gateway-Konfiguration aus gateways.csv laden"
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

if [[ ! -v "config[name]" ]] ; then
    echo "Der Hostname $HOSTNAME wurde nicht in der gateways.csv gefunden! Hat das Gateway den richtigen Hostname und besteht eine Konfiguration in der csv? Abbruch..."
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


## fastd Config
echo "- Konfigurationsdateien für fastd anpassen"

## Verzeichnis für Gateway-Partner anlegen
mkdir config/fastd/backbone/gateway

## FastD-Config anpassen
sed -i "s/10000/${config[fastdbbport]}/g" config/fastd/backbone/fastd.conf
sed -i "s/0.0.0.0/${config[ip]}/g" config/fastd/backbone/fastd.conf
sed -i "s/00:00:00:00:00:00/${config[bbmac]}/g" config/fastd/backbone/fastd.conf

sed -i "s/10000/${config[fastdport]}/g" config/fastd/v4/fastd.conf
sed -i "s/0.0.0.0/${config[ip]}/g" config/fastd/v4/fastd.conf
sed -i "s/00:00:00:00:00:00/${config[v4mac]}/g" config/fastd/v4/fastd.conf

sed -i "s/10000/${config[fastdport]}/g" config/fastd/v6/fastd.conf
# sed -i "s/0.0.0.0/${config[ip]}/g" /etc/fastd/v6/fastd.conf
sed -i "s/00:00:00:00:00:00/${config[v6mac]}/g" config/fastd/v6/fastd.conf

## FastD Secrets ablegen
echo "- fastd secrets hinterlegen"
echo "secret \"${config[fastdbbsec]}\";" > config/fastd/backbone/secret.conf
echo "secret \"${config[fastdsec]}\";" > config/fastd/v4/secret.conf
echo "secret \"${config[fastdsec]}\";" > config/fastd/v6/secret.conf


## Public-Keys der Gateways der gleichen Domäne hinterlegen
echo "- Public-Keys der Gateways der gleichen Domäne anlegen"

## Variable für DNS-Server in der Domäne
DNSSERVER=${config[ffip]}

OLDIFS=$IFS
IFS=';'
[ ! -f $INPUT ] && { echo "$INPUT Datei nicht gefunden!"; exit 99; }
while read domain nr name dns host ip ffip ipv6 ipv6gw ffipv6 fastdport fastdbbport bbmac v4mac v6mac dhcprange dhcpstart dhcpend fastdbbsec fastdbbpub fastdsec fastdpub
do
    if [ "${config[domain]}" == "$domain" ] && [ "$HOSTNAME" != "$name" ]; then
        echo "key \"$fastdbbpub\";" > config/fastd/backbone/gateway/$name
        echo "remote \"$dns\" port $fastdbbport;" >> config/fastd/backbone/gateway/$name
        DNSSERVER+=", $ffip"
    fi

done < $INPUT
IFS=$OLDIFS


## IPv6 und Netzwerkbridge in interfaces anpassen
echo "- Netzwerkkonfiguration vorbereiten (IPv6, br-ffharz)"
sed -i "s/<ipv6>/${config[ipv6]}/g" config/interfaces
sed -i "s/<ipv6gw>/${config[ipv6gw]}/g" config/interfaces
sed -i "s/<ffipv6>/${config[ffipv6]}/g" config/interfaces
sed -i "s/<ipv6gw-1>/${config[ipv6gw]::-1}/g" config/interfaces
sed -i "s/<ffip>/${config[ffip]}/g" config/interfaces


# DHCPd Konfiguration anpassen
echo "- DHCPd Konfiguration anpassen"
sed -i "s/<dhcprange>/${config[dhcprange]::-3}/g" config/dhcpd.conf
sed -i "s/<dhcpstart>/${config[dhcpstart]}/g" config/dhcpd.conf
sed -i "s/<dhcpend>/${config[dhcpend]}/g" config/dhcpd.conf
sed -i "s/<DNSSERVER>/${DNSSERVER}/g" config/dhcpd.conf
sed -i "s/<ffip>/${config[ffip]}/g" config/dhcpd.conf

## RADVD Konfiguration anpassen
## ToDo: IPv6 DNS 
sed -i "s/<ipv6gw-1>/${config[ipv6gw]::-1}/g" config/radvd.conf



## DNS
## ToDo: muss ggf. noch angepasst werden


##respondd Konfiguration anpassen
sed -i "s/<name>/${config[name]}/g" config/respondd.config.json
sed -i "s/<bbmac>/${config[bbmac]}/g" config/respondd.config.json
## ToDo: Firmware/batman-adv Version in Konfig schreiben

## Firewall anpassen
## ToDo Firewall Regeln müssen noch angepasst werden



if $fullrun; then 

    ## Paketequellen aktualisieren und Pakete installieren
    echo "- Paketquellen aktualisieren und notwendige Pakete installieren (batctl fastd bridge-utils isc-dhcp-server radvd iptables-persistent dnsmasq python3-netifaces)"
    apt update
    apt upgrade
    apt install batctl fastd bridge-utils isc-dhcp-server radvd iptables-persistent dnsmasq python3-netifaces

    echo "- batman-adv Kernelmodul Autostart aktivieren und sofort laden"
    ## batman-adv Kernel-Modul aktivieren (nach Neustart)
    echo "batman-adv" >> /etc/modules
    ## batman-adv Kernel-Modul sofort laden
    modprobe batman-adv

    ## Konfigurationsdateien an richtige Stelle kopieren
    echo "- fastd Konfigurationsdateien nach /etc/fastd kopieren"
    cp config/fastd/. /etc/fastd/ -r

    ## FastD Autostart einrichten
    echo "- fastd Autostart einrichten"
    cp config/fastd@.service /etc/systemd/system/fastd@.service
    systemctl daemon-reload
    systemctl enable fastd@backbone
    systemctl enable fastd@v4
    systemctl enable fastd@v6

    ## Netzwerkbrige anlegen
    echo "- Netzwerk-Bridge in /etc/network/interface einrichten"
    cp /etc/network/interfaces /etc/network/interfaces.old
    cat config/interfaces >> /etc/network/interfaces

    ## DHCPv4 konfigurieren
    echo "- DHCPd an br-ffharz binden und Konfigurationsdateien nach /etc/dhcp/ kopieren"
    sed -i "s/INTERFACESv4=\"\"/INTERFACESv4=\"br-ffharz\"/g" /etc/default/isc-dhcp-server
    sed -i "s/INTERFACESv6=\"\"/INTERFACESv6=\"br-ffharz\"/g" /etc/default/isc-dhcp-server
    touch /etc/dhcp/static.conf
    cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.old
    cat config/dhcpd.conf > /etc/dhcp/dhcpd.conf

    ## DHCPv6 konfigurieren
    echo "- radvd Konfigurationsdatei nach /etc kopieren"
    cp /etc/radvd.conf /etc/radvd.conf.old
    cat config/radvd.conf > /etc/radvd.conf

    ## DNS konfigurieren
    echo "- dnsmasq Konfigurationsdatei nach /etc kopieren"
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.old
    cat config/dnsmasq.conf > /etc/dnsmasq.conf

    ##respondd installieren
    echo "- respondd installieren, konfigurieren und Autostart einrichten"
    git clone https://github.com/FreifunkHochstift/ffho-respondd.git /opt/respondd
    cp config/respondd.config.json /opt/respondd/config.json

    cp /opt/respondd/respondd.service.example /lib/systemd/system/respondd.service
    sed -i "s/srv\/ffho-/opt\//g" /lib/systemd/system/respondd.service
    systemctl daemon-reload
    systemctl enable respondd

    ##Firewall-Regeln laden
    

    ## IP Forwarding aktivieren
    echo "- IPForwarding aktivieren"
    sed -i "s/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g" /etc/sysctl.conf
    sed -i "s/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/g" /etc/sysctl.conf


    ## Ende
    echo "Fertig! --> reboot"
fi







