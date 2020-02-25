# Einrichtung eines Proxmox Hostserver bei Hetzner für virtuelle Gateways

## Hetzner Config Mode

Im Config Mode ist als Installations-Image other -> Proxmox (Buster) auszuwählen.

In der Config-Datei den Hostnamen auf HS?? ändern

### Partitionierung

Die Partitionierung richten wir entsprechend der Proxmox Standard-Partitionierung ein.

#### Hardware-Raid oder 1 Festplatte

Standardkonfig mit # auskommentieren (alle Zeilen mit PART und LV).  
Folgende Zeilen einfügen:

    PART /boot ext4 512M
    PART lvm pve all

    LV pve swap swap swap 8G
    LV pve root / ext4 100G

#### Software-Raid mit 2 Festplatten

Folgende Konfiguration verwenden:

    PART /boot ext3 4G
    PART lvm vg0 116G
    PART lvm vg1 all

    LV vg0 root / ext3 100G
    LV vg0 swap swap swap 16G
    LV vg1 vz /var/lib/vz ext3 all

Mit dem Befehl *cat /proc/mdstat* kann der Status der Initialisierung ausgegeben werden.
Mit dem Befehl *mdadm -D /dev/mdX* können weitere Details über ein Array ausgegeben werden

## Grundkonfiguration

### root Passwort

root Password mit *passwd* ändern (bspw. 20 Zeichen). Dies wird für den Login auf der Proxmox Konfigurationsoberfläche benötigt.

### Storage anlegen (bei Hardware-RAID)

Daten-Speicher für virtuelle Maschinen anlegen. Die Größe kann/sollte entsprechend der Gegebenheiten angepasst werden.

    lvcreate -L 1024G -n data pve
    lvconvert --type thin-pool pve/data

In der Proxmox-Oberfläche muss er unter *Rechenzentrum -> Storage -> hinzufügen -> LVM-Thin* mit folgenden Einstellungen hinzugefügt werden:

* ID = local-lvm
* Volume-Gruppe = lvm
* Thin Pool = data

### SSH

SSH-Config */etc/ssh/sshd-config* anpassen:

* Port auf 65333 ändern

Wenn nicht bereits bei der Hetzner-Einrichtung erfolgt, können die SSH-Key's weiterer Admins hinterlegt werden.

### fail2ban

Zum absichern des SSH-Zugang fail2ban installieren:

    apt install fail2ban

Zum konfigurieren legen wir uns eine eigene Konfigurationsdatei *jail.local* an, da die Standard-Config *jail.conf* bei jeder Packetaktualisierung überschrieben wird:

    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

Anschließend kann die Konfiguration dem eigenen Sicherheitsanspruch angepasst werden und mit *systemctl restart fail2ban.service* übernommen werden.

### Netzwerk

Es wird ein zusätzliches /56 IPv6 Subnetz (in diesem Beispiel 2a01:affe:affe:ff00::/56) von Hetzner (einmalig 49€) benötigt. Dies kann man einfach per Ticket zu jedem Server buchen.

Der einfachheit halber wird der Name der Netzwerkkarte auf eth0 geändert:

    sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"net.ifnames=0 biosdevname=0\"/g" /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg

Wichtig, es muss anschließend in der */etc/network/interfaces* der Adaptername mit *eth0* ersetzt werden.

Es muss eine Netzwerk-Bridge angelegt werden, an der die VM's angebunden werden. Die Bridge erzeugt quasi ein "internes" Netzwerk, an der alle VM's angebunden sind. Dem Netzwerk geben wir den IP-Bereich 192.168.0.0/16 und aktivieren NAT, damit die VM's auch das Internet erreichen. Nachfolgend eine Beispiel */etc/network/interfaces*:

    source /etc/network/interfaces.d/*

    auto lo
    iface lo inet loopback

    iface lo inet6 loopback

    auto eth0
    iface eth0 inet static
            address  x.x.x.x
            netmask  x
            gateway  x.x.x.x
            up route add -net x.x.x.x netmask 255.255.255.224 gw x.x.x.x dev eth0

    iface eth0 inet6 static
            address  x:x:x:x::2
            netmask  128
            gateway  fe80::1
            # zusätzliche IPv6 (am besten die erste Adresse des Subnet) aus zusätzlichem Subnet auf eth0 binden, 
            up ip addr add 2a01:affe:affe:ff00::2/128 dev eth0
            up sysctl -p

    auto vmbr0
    iface vmbr0 inet static
            address  192.168.0.1
            netmask  16
            bridge-ports none
            bridge-stp off
            bridge-fd 0

            # Ausgehende IPv4 Pakete maskieren
            post-up iptables -A POSTROUTING -t nat -o eth0 -j MASQUERADE

            # Port-Forwarding (fastd-Tunnel) zu VM (siehe unten)
            post-up iptables -t nat -A PREROUTING -i eth0 -p udp --dport 10101 -j DNAT --to 192.168.1.1:10101
            post-down iptables -t nat -D PREROUTING -i eth0 -p udp --dport 10101 -j DNAT --to 192.168.1.1:10101

    iface vmbr0 inet6 static
            # zusätzliches v6 Subnetz an Bridge binden
            address  2a01:affe:affe:ff00::2
            netmask  56
            # IPv6 Route eines /64 Netzes zu einer VM, welche dieses Netz per SLAAC verteilen kann...
            up ip route add 2a01:affe:affe:ff11::/64 via 2a01:affe:affe:6f11::2

Wenn die VM-Bridge von mehreren Host-Servern über das Hetzner VLAN miteinander verbunden werden sollen muss die */etc/network/interfaces* noch um folgenden Eintrag erweitert werden:

    auto eth0.4000
    iface eth0.4000 inet manual
            vlan-raw-device eth0
            mtu 1400

Und die Bridge vmbr0 muss an die Schnittstelle gebunden werden. Dafür muss der Eintrag *bridge-ports none* in *bridge-ports eth0.4000* 

Abschließend muss noch das IP-Forwarding aktivieren, damit die Pakete auch weitergeleitet werden.
Dafür ist in der Datei */etc/sysctl.d/99-hetzner.conf* und/oder */etc/sysctl.conf* folgendes einzustellen:

    net.ipv4.ip_forward=1
    net.ipv6.conf.all.forwarding=1

Das erfolgreiche setzen der Werte kann mit *sysctl -p* überprüft werden.

### Firewall

Es sollten alle Port's außer der SSH-Port (65333), ICMP und die fastd-Port gesperrt werden. Die zugelassenen Port's legt man in der Proxmox-Oberfläche unter Rechenzentrum->Firewall an.  
Anschließend aktiviert man die Firewall unter Rechenzentrum->Firewall-Optionen.
Am besten das ganze mal bei einem bereits bestehenden Proxmox anschauen...

## Vorbereitung für VM's

### ISO-Download

Um auf Basis von Debian eine VM zu erstellen muss noch die entsprechende ISO (Link evtl. anpassen) runtergeladen werden. Dies geht einfach mit:

    cd /var/lib/vz/template/iso
    wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-10.3.0-amd64-netinst.iso

### Port-Forwarding

Damit ein bestimmter Port zur VM weitergeleitet wird, muss für jede VM jeweils folgendes in die */etc/network/interfaces* in dem unter Netzwerk eingefügten Teil unter der NAT-Regel eingefügt werden:

    post-up iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 10101 -j DNAT --to 192.168.1.1:10101
    post-down iptables -t nat -D PREROUTING -i eth0 -p tcp --dport 10101 -j DNAT --to 192.168.1.1:10101

Wobei *eth0* die phys. Netzwerkkarte, *10101* der Zielport und *192.168.1.1* die IP der VM ist. Dies sollte entsprechend der Gegebenheiten angepasst werden.

## Abschluss

Nachdem alle obigen Aufgaben erledigt sind, muss der Server neugestartet werden. Anschließend können über die Proxmox-Oberfläche VM's angelegt werden.
