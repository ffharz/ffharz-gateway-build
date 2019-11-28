# FFHarz-Gateway-Build - in Entwicklung

Script zum automatischen installieren von Freifunk Harz Gateways.

## Vorraussetzungen

Vorraussetzung ist eine frisch installierte VM mit Debian 10 Buster auf einer ensprechend vorbereiteten Proxmox-Installation (siehe hostserver-einrichten.md)  
Zusätzlich wird eine *gateways.csv* benötigt, welche alle Informationen zu den Gateways enthält.
Diese hat folgende Struktur:

| domain | nr | name | dns | host | ip | fastdport | fastdbbport | bbmac | v4mac | v6mac | dhcprange | dhcpstart | dhcpend | fastdbbsec | fastdbbpub | fastdbbsec | fastdbbpub |
| - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
Domäne | Lfd-Nr | Name | DNS-Name | Host | IP | FastD-Port | FastD-BBPort | FastD-MAC-BB | FastD-MAC-v4 | FastD-MAC-v6 | DHCP-Bereich | DHCP-Start | DHCP-Ende | FastD BB Secret | FastD BB Public | FastD Client Secret | FastD Client Public |

## Nutzung

Installation von GIT:

     apt install git

Repository clonen:

    git clone https://github.com/ffharz/ffharz-gateway-build.git

Anschließend in das Verzeichnis wechseln und die *install.sh* ausführbar machen:

    cd ffharz-gateway-build
    chmod +x install.sh

Die *gateways.csv* muss im gleichen Verzeichnis wie die *install.sh* liegen.
Als Vorlage kann die gateways.csv.empty genutzt werden. Eine gefüllte Liste für das Freifunk Harz Netz liegt in der Freifunk Harz Cloud unter Dokumentation.
