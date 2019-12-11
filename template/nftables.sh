#!/bin/bash

nft -f /etc/nftables.conf

## filter INPUT ####################################################################
## IPv4 Filter Table anlegen und Eingehend alles verwerfen
nft add table ip filter
nft add chain ip filter INPUT { type filter hook input priority 0\; policy drop\; }
nft add chain ip filter FORWARD { type filter hook forward priority 0\; policy accept\; }
nft add chain ip filter OUTPUT { type filter hook output priority 0\; policy accept\; }

## Eingehend von lo, bat0, mesh-vpn-ipv4, mesh-vpn-ipv4, backbone und eth0 Zulassen
nft add rule ip filter INPUT iifname "lo" accept
nft add rule ip filter INPUT iifname "bat0" accept
nft add rule ip filter INPUT iifname "mesh-vpn-ipv4" accept
nft add rule ip filter INPUT iifname "mesh-vpn-ipv6" accept
nft add rule ip filter INPUT iifname "backbone" accept
nft add rule ip filter INPUT iifname "eth0" accept

## Alle privaten IP-Bereiche, ausser dem FF-Netz, von br-ffharz verwerfen
nft add rule ip filter INPUT iifname "br-ffharz" ip saddr != <dhcprange-3>/16 counter drop

## DNS, SSH und PING aus FF-Netz an lokalen Server erlauben
nft add rule ip filter INPUT iifname "br-ffharz" icmp type echo-request accept
nft add rule ip filter INPUT iifname "br-ffharz" udp dport domain accept
nft add rule ip filter INPUT iifname "br-ffharz" tcp dport ssh accept

nft add rule ip filter INPUT ct state invalid counter reject
nft add rule ip filter INPUT ct state related,established accept

## filter FORWARD ##################################################################
## IPv4 Forward Table anlegen

## Private Adress-Bereiche nicht weiterleiten
nft add rule ip filter FORWARD iifname "br-ffharz" oifname "eth0" ip daddr 10.0.0.0/8 counter drop
nft add rule ip filter FORWARD iifname "br-ffharz" oifname "eth0" ip daddr 192.168.0.0/16 counter drop
nft add rule ip filter FORWARD iifname "br-ffharz" oifname "eth0" ip daddr 172.16.0.0/12 counter drop
nft add rule ip filter FORWARD iifname "br-ffharz" oifname "eth0" ip daddr 169.254.0.0/16 counter drop
nft add rule ip filter FORWARD iifname "br-ffharz" oifname "eth0" ip daddr 100.64.0.0/10 counter drop

nft add rule ip filter FORWARD ct state invalid counter reject
nft add rule ip filter FORWARD ct state related,established accept

## filter OUTPUT ###################################################################
nft add rule ip filter OUTPUT ct state invalid counter reject
nft add rule ip filter OUTPUT ct state related,established accept

## nat POSTROUTING #################################################################
## NAT Table anlegen
nft add table nat
nft add chain nat postrouting { type nat hook postrouting priority 100 \; }
## Masquerading für alle ausgehenden Pakete aus FF-Netz aktivieren
#nft add rule nat postrouting masquerade
nft add rule nat postrouting oifname "eth0" ip saddr <dhcprange> masquerade

