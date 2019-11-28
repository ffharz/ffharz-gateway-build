# Einrichtung eines Proxmox Hostserver für virtuelle Gateways

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

ToDo

## Grundkonfiguration

### root Passwort

root Password mit *passwd* ändern (bspw. 20 Zeichen). Dies wird für den Login auf der Proxmox Konfigurationsoberfläche benötigt.

### Packetquellen anpassen

Packetquellen für Proxmox hinzufügen:

    echo "deb http://download.proxmox.com/debian buster pve-no-subscription" >> /etc/apt/sources.list
    wget -q http://download.proxmox.com/debian/proxmox-ve-release-6.x.gpg -O /etc/apt/trusted.gpg.d/proxmox-ve-release-6.x.gpg
    apt update
    apt upgrade

### Storage anlegen

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

Es muss eine Netzwerk-Bridge angelegt werden, an der die VM's angebunden werden. Die Bridge erzeugt quasi ein "internes" Netzwerk, an der alle VM's angebunden sind. Dem Netzwerk geben wir den IP-Bereich 192.168.0.0/16 und aktivieren NAT, damit die VM's auch das Internet erreichen. Dafür muss folgendes in die */etc/network/interfaces* hinzugefügt werden:

    auto vmbr0
    iface vmbr0 inet static
        address  192.168.0.1
        netmask  16
        bridge-ports none
        bridge-stp off
        bridge-fd 0

        #NAT aktivieren
        post-up iptables -A POSTROUTING -t nat -j MASQUERADE

    iface vmbr0 inet6 static
        # IPv6 des Servers eintragen
        address  2a01:4f8:xxx:xxxx::x
        netmask  64

Anschließend muss noch das IP-Forwarding aktivieren, damit die Pakete auch weitergeleitet werden.
Dafür ist in der Datei */etc/sysctl.d/99-hetzner.conf* und/oder */etc/sysctl.conf* folgendes einzustellen:

    net.ipv4.ip_forward=1
    net.ipv6.conf.all.forwarding=1

## Vorbereitung für VM's

### ISO-Download

Um auf Basis von Debian eine VM zu erstellen muss noch die entsprechende ISO (Link evtl. anpassen) runtergeladen werden. Dies geht einfach mit:

    cd /var/lib/vz/template/iso
    wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-10.2.0-amd64-netinst.iso

### Port-Forwarding

Damit ein bestimmter Port zur VM weitergeleitet wird, muss für jede VM jeweils folgendes in die */etc/network/interfaces* in dem unter Netzwerk eingefügten Teil unter der NAT-Regel eingefügt werden:

    post-up iptables -t nat -A PREROUTING -i enp4s0 -p tcp --dport 10101 -j DNAT --to 192.168.1.1:10101
    post-down iptables -t nat -D PREROUTING -i enp4s0 -p tcp --dport 10101 -j DNAT --to 192.168.1.1:10101

Wobei *enp4s0* die phys. Netzwerkkarte, *10101* der Zielport und *192.168.1.1* die IP der VM ist. Dies sollte entsprechend der Gegebenheiten angepasst werden.

## Abschluss

Nachdem alle obigen Aufgaben erledigt sind, muss der Server neugestartet werden. Anschließend können über die Proxmox-Oberfläche VM's angelegt werden.