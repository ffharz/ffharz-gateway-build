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

Der einfachheit halber wird der Name der Netzwerkkarte auf eth0 geändert:

    sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"net.ifnames=0 biosdevname=0\"/g" /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg

Wichtig, es muss anschließend in der */etc/network/interfaces* der Adaptername mit *eth0* ersetzt werden.

Es muss eine Netzwerk-Bridge angelegt werden, an der die VM's angebunden werden. Die Bridge erzeugt quasi ein "internes" Netzwerk, an der alle VM's angebunden sind. Dem Netzwerk geben wir den IP-Bereich 192.168.0.0/16 und aktivieren NAT, damit die VM's auch das Internet erreichen. Dafür wird die Datei */etc/network/interfaces/vmbr0.cfg* mit folgendem Inhalt erstellt:

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
        # IPv6 des Servers +1 eintragen
        address  2a01:4f8:xxx:xxxx::3
        netmask  64
        up ip -6 route add 2a01:4f8:xxx:xxxx::/64 dev vmbr0

Anschließend muss noch das IP-Forwarding aktivieren, damit die Pakete auch weitergeleitet werden.
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
    wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-10.2.0-amd64-netinst.iso

### Port-Forwarding

Damit ein bestimmter Port zur VM weitergeleitet wird, muss für jede VM jeweils folgendes in die */etc/network/interfaces* in dem unter Netzwerk eingefügten Teil unter der NAT-Regel eingefügt werden:

    post-up iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 10101 -j DNAT --to 192.168.1.1:10101
    post-down iptables -t nat -D PREROUTING -i eth0 -p tcp --dport 10101 -j DNAT --to 192.168.1.1:10101

Wobei *eth0* die phys. Netzwerkkarte, *10101* der Zielport und *192.168.1.1* die IP der VM ist. Dies sollte entsprechend der Gegebenheiten angepasst werden.

## Abschluss

Nachdem alle obigen Aufgaben erledigt sind, muss der Server neugestartet werden. Anschließend können über die Proxmox-Oberfläche VM's angelegt werden.
