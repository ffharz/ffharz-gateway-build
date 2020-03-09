#!/bin/bash
#/usr/lib/check_mk_agent/local
## Orginal von https://raw.githubusercontent.com/eulenfunk/check_mk/master/supernode angepasst für Freifunk Harz
export LANG=de_DE.UTF-8

function confline # get first line from file $1 mathing $2, stripped of # and ; comment lines, stripped spaces and tabs down to spaces, remove trailing ;
{
 echo $(cat $1|grep -v '^$\|^\s*\#'|sed -e "s/[[:space:]]\+/ /g"|sed s/^\ //|sed s/\;//|grep -i "$2"|head -n 1)
}

function ati # ipv4 to longint
{
 ip4=$1; ipno=0
 for (( i=0 ; i<4 ; ++i )); do
   ((ipno+=${ip4%%.*}*$((254**$((3-${i})))))) # .0 .255 should not be counted
   ip4=${ip4#*.}
  done
 echo $ipno
}

## static data
bat_version=$(batctl -v);
fastd_version=$(fastd -v|cut -d ' ' -f 2);
kernel=$(uname -r);
release=$(lsb_release -ds);

## debian-Status
echo "0 Debian-Release Debian-Release=$release; $release - Kernel $kernel"
## debian patch status
reboot=0
if [ -x  /var/run/reboot-required.pkgs ] ; then
  reboot=$(cat /var/run/reboot-required.pkgs|wc -l)
 fi
supdates=0
supdates=$(apt-get upgrade -s 2>/dev/null| grep ^Security |wc -l)
nupdates=0
nupdates=$(apt-get upgrade -s 2>/dev/null| grep ^Inst |wc -l)
echo "P Debian-Patchstatus SecurityUpdates-waiting=$supdates.0;0:0.5;0:1|RegularUpdates-waiting=$nupdates.0;0:10;0:15|Reboot-waiting=$reboot.0;0:0.5;0:1"


## Batman
echo "0 Batman-Version Version=$bat_version; $bat_version"
list=$(ls -F /sys/kernel/debug/batman_adv|grep /)
for i in $list; do
  z=$(ls /sys/kernel/debug/batman_adv/$i|wc -l)
  if [ $z -ge 9 ]; then
    b=$(echo $i|cut -d '/' -f1)
    router=$(($(batctl -m $b o|wc -l)-2 ))
    clients=$(grep -cEo "\[.*W.*\]+" /sys/kernel/debug/batman_adv/$b/transtable_global)
    gateways=$(( $(batctl -m $b gwl|wc -l) -1 ))
    ips=$(( $(batctl -m $b dc|wc -l) - 2))
    wlow=$(( $router * 20 / 100 ))
    clow=$(( $router * 5 / 100 ))
    wlimit=$(( $router * 5 ))
    climit=$(( $router * 10 ))
    echo "P Batman-$b Router=$router.0;5:250;1:500|Clients=$clients.0;$wlow.0:$wlimit.0;$clow.0:$climit.0|Gateways=$gateways.0;0:3;0:5;|IPs=$ips.0";
   fi;
 done

## Fastd
echo "0 Fastd_Version Version=$fastd_version; Fastd $fastd_version ";
fastdp=/etc/fastd
list=$(ls -F $fastdp|grep /|cut -d '/' -f 1)
for fasti in $list ; do
  clients=$(nc -U $(cat $fastdp/$fasti/fastd.conf|grep -v '^$\|^\s*\#'|sed -e "s/[[:space:]]\+/ /g"|sed s/^\ //|sed s/\;//|grep -i 'status socket'|cut -d '"' -f 2)|grep '"established"' -o|wc -l);
  interface=$(confline $fastdp/$fasti/fastd.conf interface|cut -d '"' -f 2)
  mtu=$(confline $fastdp/$fasti/fastd.conf mtu|cut -d ' ' -f 2|cut -d ';' -f1)
  port=$(confline $fastdp/$fasti/fastd.conf bind|cut -d ':' -f 2|cut -d ' ' -f1)
  limit=$(confline $fastdp/$fasti/fastd.conf 'peer limit'|cut -d ' ' -f 3|cut -d ';' -f1)
  climit=$(( $limit * 95 / 100 ))
  wlimit=$(( $limit * 90 / 100 ))
  clow=$(( $limit / 100 ))
  wlow=$(( $limit * 5 / 100 ))
  echo "P Fastd_Clients_$interface Clients=$clients.0;$wlow:$wlimit;$clow:$climit; Interface: $interface, Port: $port, MTU: $mtu, Peer Limit: $limit"
 done

## isc-dhcpd-server leases
# needs script https://raw.githubusercontent.com/eulenfunk/scripts/master/dhcpleases at /opt/
if [ -r /opt/dhcpleases ] ; then
  dhcpconf=/etc/dhcp/dhcpd.conf
  dhcprange=$(confline $dhcpconf range)
  dhcpstart=$(echo $dhcprange|cut -d" " -f2)
  dhcpend=$(echo $dhcprange|cut -d" " -f3)
  totalleases=$(($(ati $dhcpend) - $(ati $dhcpstart)))
  activeleases=$(/opt/dhcpleases|grep "^| Total"|cut -d":" -f2|sed s/\ //)
  remainingleases=$(($totalleases - $activeleases))
  actwarn=$(($totalleases * 75 / 100))
  actcrit=$(($totalleases * 90 / 100))
  echo "P Dhcp-Leases active-leases=$activeleases.0;5:$actwarn;1:$actcrit active:$activeleases remaining:$remainingleases pool=$totalleases";
 fi


## Logins
logincount=$(who|wc -l)
logout="0 LocalUser CurrentLogins=$logincount.0; CurrentLogins:$logincount"
i=0
TFILE="/tmp/$(basename $0).$$.tmp"
who -u>$TFILE
while read line; do
  i=$(( i + 1))
  line=$(echo $line|sed s/\ +//|tr -s " ")
  user=$(echo $line|cut -d" " -f1)
  tty=$(echo $line|cut -d" " -f2)
  idle=$(echo $line|cut -d" " -f6)
  ip=$(echo $line|cut -d" " -f8)
  logout="$logout\n login-$i-user:$user login-$i-tty:$tty login-$i-idle:$idle login-$i-source:$ip"
 done<$TFILE
rm $TFILE
#echo "$logout"