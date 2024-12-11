#!/bin/bash
#
# 10 Dec 2024
# 계엄과 탄핵의 사이 어딘가에서
# Chul-Woong Yang
#
# 테스트 환경
# client network: 10.10.1.0/24 netns client
# server network: 10.10.2.0/24 netns server
# router network: 10.10.10.0/24 netns router
# hub network: netns hub
#
# Client 10.10.1.2/24 -- 10.10.1.1/24 CGW 10.100.1.1 -- br 10.100.1.101 RGW br 10.100.1.101 -- 10.100.1.3 Router
# Server 10.20.1.2/24 -- 10.20.1.1/24 SGW 10.100.1.2 -- br 10.100.1.101 RGW br 10.100.1.101 -- 10.100.1.3 Router
#
# bridge rule
# RGW br0 -- cgw-veth0, sgw-veth0, router-veth0
# participating interface should not have ip addr.
# only bridge must have ip addr.
#
# route rule
# Client, Server, Router --> default route to CGW, SGW, RGW
# CGW
#  - default route to RGW(10.100.1.3) veth0
#  - 10.10.1.0/24 to Client(10.10.1.2) client-veth0
#  - 10.20.1.0/24 to Server(10.100.1.2) veth0
# SGW
#  - default route to RGW(10.100.1.3) veth0
#  - 10.10.1.0/24 to Client(10.100.1.1) veth0
#  - 10.20.1.0/24 to Server(10.20.1.2) server-veth0
# RGW
#  - 10.10.1.0/24 to CGW(10.100.1.1) cgw-veth0
#  - 10.20.1.0/24 to SGW(10.100.1.2) sgw-veth0
#
#

# exit on error
set -e
trap 'echo line $LINENO exits with code $?.' ERR

debug=0
vpp="vpp"
ip="ip"
raw_ip=$ip
iptables="iptables"
raw_iptables=$iptables
vppctl="sudo vppctl"
echo=""
if [ "$debug" -ne 0 ]; then
    ip="echo $ip"
    iptables="echo $iptables"
    vppctl="echo $vppctl"
    echo="echo"
fi

vppconf="vpp.conf"
nic_names=("veth0" "veth1")
nsc="client"
nss="server"
nsr="router"
nsr2="router2"
nscgw="cgw"
nssgw="sgw"
nsrgw="rgw"
entity_nss=($nsc $nss $nsr $nsr2)
entity_nets=("10.10.1.0/24" "10.10.2.0/24" "10.100.1.0/24" "10.200.1.0/24")
entity_addrs=("10.10.1.2/24" "10.10.2.2/24" "10.100.1.2/24" "10.200.1.2/24")
hub_addrs=("10.10.1.1/24" "10.10.2.1/24" "10.100.1.1/24" "10.200.1.1/24")
router_ids=("vpp1" "vpp2")
aux_srv_addr="10.10.2.3"

function exec_ns {
    local ns="$1"; shift
    $echo sudo $raw_ip netns exec $ns $@
}
function ip_ns {
    local ns="$1"; shift
    exec_ns $ns $raw_ip $@
}
function vppctl_with {
    local id="$1"; shift
    $vppctl -s /run/vpp/$id.sock $@
}

function generate_mac5() {
    local head="$1"
    if [[ -n "$head" ]]; then
	head="${head}":
    fi
    printf "${head}00:00:%02x:%02x:%02x\n" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
}

function make_ns {
    local ns="$1"; shift
    $ip netns del $ns || true # ignore non-existing ns deletion
    $ip netns add $ns
    ip_ns $ns link set lo up
    echo "make_ns: $ns"
}

function make_vethpair() {
    local nic_name="$1"; shift
    local ns="$1"; shift
    local peer_ns="$1"; shift
    local addr="$1"; shift
    local peer_addr="$1"; shift
    local route_dest="$1"

    echo "make vethpair: $nic_name $ns $peer_ns $addr $peer_addr $route_dest"
    MAC=$(generate_mac5)
    $ip link add $nic_name type veth peer name $ns-$nic_name
    $ip link set dev $nic_name address 02:$MAC
    $ip link set dev $ns-$nic_name address 22:$MAC
    $ip link set $nic_name netns $ns
    $ip link set $ns-$nic_name netns $peer_ns
    # my addr
    ip_ns $ns addr add $addr dev $nic_name
    if [[ $peer_addr != "none" ]]; then
	ip_ns $peer_ns addr add $peer_addr dev $ns-$nic_name
    fi
    ip_ns $ns link set $nic_name up
    ip_ns $peer_ns link set $ns-$nic_name up
    # and default route
    if [[ -n $route_dest ]]; then
	local peer_host=${peer_addr%/*}	# remove mask
	ip_ns $ns route add $route_dest via $peer_host dev $nic_name
    fi
    exec_ns $ns sysctl -qw net.ipv4.ip_forward=1
}

function make_vethpair2() {
    local nic_name="$1"; shift
    local ns="$1"; shift
    local peer_ns="$1"; shift
    local addr="$1"; shift
    local peer_addr="$1"; shift
    local peer_host=${peer_addr%/*}	# remove mask
    local route_dest="$1"

    echo "make vethpair: $nic_name $ns $peer_ns $addr $peer_addr $route_dest"
    $ip link add $nic_name type veth peer name $ns-$nic_name
    MAC=$(generate_mac5)
    MAC2=$(generate_mac5)
    $ip link set dev $nic_name address 02:$MAC
    $ip link set dev $ns-$nic_name address 02:$MAC2
    $ip link set $nic_name netns $ns
    $ip link set $ns-$nic_name netns $peer_ns
    # my addr
    #ip_ns $ns addr add $addr dev $nic_name
    ip_ns $peer_ns addr add $peer_addr dev $ns-$nic_name
    ip_ns $ns link set $nic_name up
    ip_ns $peer_ns link set $ns-$nic_name up
    exec_ns $ns sysctl -qw net.ipv4.ip_forward=1
}

function dns_setup() {
    local ns="$1"; shift
    path=/etc/netns/$ns
    mkdir -m 644 -p $path
    echo "nameserver 8.8.8.8" > $path/resolv.conf
}

function create_vpp_interface() {
    local id="$1"; shift
    local net="$1"; shift
    local addr="$1"; shift
    local router="$1"; shift
    local nic="$1"; shift

    echo vppctl_with $id create host-interface name $nic #num-rx-queues 2 num-tx-queues 2
    vppctl_with $id create host-interface name $nic #num-rx-queues 2 num-tx-queues 2    
    vppctl_with $id set interface ip address host-$nic $router    
    vppctl_with $id set interface state host-$nic up
    # add routing
    vppctl_with $id ip route add $net via ${addr%/*}
    echo $nic done
}
function usage {
    echo "Usage: $0 {netns|vpp|ping|pong}"
}
rc=255
case "$1" in
    test)
	echo $(generate_mac)
	echo $(generate_mac 11)
	;;
    ns|netns)
	for ns in $nsc $nsr $nsr2 $nss $nscgw $nssgw $nsrgw; do
	    make_ns $ns
	    $echo dns_setup $ns
	done
	make_vethpair veth0 $nsc $nscgw 10.10.1.2/24 10.10.1.1/24 default
	make_vethpair veth0 $nss $nssgw 10.20.1.2/24 10.20.1.1/24 default
	make_vethpair veth0 $nscgw $nsrgw 10.100.1.1/24 none
	make_vethpair veth0 $nssgw $nsrgw 10.100.1.2/24 none
	make_vethpair veth0 $nsr $nsrgw 10.100.1.3/24 none
	#make_vethpair veth0 $nsr2 $nsrgw 10.100.1.4/24 10.100.1.104/24 default

	# bridge domain
	ip_ns $nsrgw link add name br0 type bridge
	ip_ns $nsrgw link set br0 up
	ip_ns $nsrgw link set cgw-veth0 master br0
	ip_ns $nsrgw link set sgw-veth0 master br0
	ip_ns $nsrgw link set router-veth0 master br0
	ip_ns $nsrgw addr add 10.100.1.101/24 dev br0

	# routes
	ip_ns $nscgw route add default via 10.100.1.3 dev veth0
	ip_ns $nssgw route add default via 10.100.1.3 dev veth0
	ip_ns $nsrgw route add 10.10.1.0/24 via 10.100.1.1 dev br0
	ip_ns $nsrgw route add 10.20.1.0/24 via 10.100.1.2 dev br0
	ip_ns $nsr route add default via 10.100.1.101 dev veth0
	
	#ip_ns $nscgw route add 10.10.1.0/24 via 10.10.1.2 dev client-veth0
	#ip_ns $nssgw route add 10.20.1.0/24 via 10.20.1.2 dev server-veth0
	#ip_ns $nsrgw route add 10.10.1.0/24 via 10.100.1.1 dev cgw-veth0
	#ip_ns $nsrgw route add 10.20.1.0/24 via 10.100.1.2 dev sgw-veth0
	#ip_ns $nsrgw route add 10.100.1.1 dev cgw-veth0
	#ip_ns $nsrgw route add 10.100.1.2 dev sgw-veth0
	#ip_ns $nsrgw route add 10.100.1.3 dev router-veth0

	# ip_forward &proxy-arp
	exec_ns $nsrgw sysctl -w net.ipv4.ip_forward=1
	exec_ns $nsrgw sysctl -w net.ipv4.conf.cgw-veth0.proxy_arp=1
	exec_ns $nsrgw sysctl -w net.ipv4.conf.sgw-veth0.proxy_arp=1
	exec_ns $nsrgw sysctl -w net.ipv4.conf.router-veth0.proxy_arp=1
	
	exec_ns $nsrgw sysctl -w net.ipv4.conf.br0.send_redirects=0
	exec_ns $nsrgw sysctl -w net.ipv4.conf.all.send_redirects=0
	exec_ns $nsr sysctl -w net.ipv4.conf.veth0.send_redirects=0
	exec_ns $nsr sysctl -w net.ipv4.conf.all.send_redirects=0

	# server additional address
	ip_ns $nss addr add $aux_srv_addr dev veth0
	;;
    gdb)
	exec_ns $nsr pkill vpp || true
	(cd /home/vagrant/vpp-dev; exec_ns $nsr make debug)
	;;
    vpp)
	#exec_ns $nsr pkill vpp || true
	#exec_ns $nsr $vpp -c $vppconf
	exec_ns $nsr pkill vpp || true
	exec_ns $nsr $vpp -c vpp1.conf
	exec_ns $nsr $vpp -c vpp2.conf
	sleep 2
	create_vpp_interface vpp1 10.100.1.0/24 10.100.1.3/24 10.100.1.103/24 veth0
	create_vpp_interface vpp2 10.100.1.0/24 10.100.1.4/24 10.100.1.103/24 veth0
	
	for i in ${!router_ids[@]}; do
	id=${router_ids[$i]}
	# sample acl rule
	vppctl_with $id ip route add ${aux_srv_addr}/32 via ${entity_addrs[1]%/*}
	targets=(10.10.1.1 10.10.1.2 10.10.2.2 10.10.2.1)
	rule=""
	rule1=""
	for t in ${targets[@]}; do
	    #rule="$rule permit+reflect proto 6 dst $t/32," # icmp
	    rule="$rule permit+reflect proto 6 dst $t/32 desc {$t} ," # icmp
	    #rule="$rule permit proto 6 dst $t/32 desc {$t}," # icmp
	    rule1="$rule1 deny proto 6 src $t/32 desc {hmm-$t} ," # icmp
	done
	rule=${rule%,}
	rule1=${rule1%,}
	echo vppctl_with $id set acl-plugin acl $rule
	vppctl_with $id set acl-plugin acl $rule tag example_permit_0
	vppctl_with $id set acl-plugin acl $rule1 tag example_permit_1
	vppctl_with $id set acl-plugin acl deny # tag example_deny_0
	#$vppctl set acl-plugin acl permit # tag example_deny_0
	vppctl_with $id set acl-plugin interface host-veth0 input acl 0
	vppctl_with $id set acl-plugin interface host-veth0 input acl 2
	vppctl_with $id set acl-plugin interface host-veth0 output acl 0
	vppctl_with $id set acl-plugin interface host-veth0 output acl 2
	vppctl_with $id set acl-plugin reclassify-sessions 1
	vppctl_with $id show acl-plugin interface sw_if_index 1 acl
	done
	vppctl_with vpp1 set acl-plugin log enable
	vppctl_with vpp1 set acl-plugin timeout tcp 1 udp 1 tcptrans 1
	# connect two vpps
	vppctl_with vpp1 create interface memif id 0 master
	vppctl_with vpp1 set interface state memif0/0 up
	vppctl_with vpp1 set interface ip address memif0/0 10.10.10.1/24 
	vppctl_with vpp2 create interface memif id 0 slave
	vppctl_with vpp2 set interface state memif0/0 up
	vppctl_with vpp2 set interface ip address memif0/0 10.10.10.2/24
	# set HA setting
	vppctl_with vpp1 acl-plugin ha listener 10.10.10.1:1234
	vppctl_with vpp1 acl-plugin ha failover 10.10.10.2:2345
	vppctl_with vpp2 acl-plugin ha listener 10.10.10.2:2345
	vppctl_with vpp2 acl-plugin ha failover 10.10.10.1:2345
	;;
    vpp2)
	for i in ${!entity_nss[@]}; do
	    $vppctl create host-interface name ${entity_nss[i]}-$nic_name
	    echo $vppctl create host-interface name ${entity_nss[i]}-$nic_name
	    $vppctl set interface ip address host-${entity_nss[i]}-$nic_name ${router_addrs[i]}
	    $vppctl set interface state host-${entity_nss[i]}-$nic_name up
	    # add routing
	    $vppctl ip route add ${entity_nets[i]} via ${entity_addrs[i]%/*}
	done
	# sample acl rule
	$vppctl ip route add ${aux_srv_addr}/32 via ${entity_addrs[1]%/*}
	targets=(10.10.1.1 10.10.1.2 10.10.2.2 10.10.2.1)
	rule=""
	for t in ${targets[@]}; do
	    rule="$rule permit+reflect proto 6 dst $t/32 ," # icmp
	done
	rule=${rule%,}
	echo $vppctl set acl-plugin acl $rule
	$vppctl set acl-plugin acl $rule
	$vppctl set acl-plugin acl deny
	$vppctl set acl-plugin interface host-${entity_nss[0]}-$nic_name input acl 0
	$vppctl set acl-plugin interface host-${entity_nss[0]}-$nic_name input acl 1
	$vppctl show acl-plugin interface sw_if_index 1 acl
	;;
    ping)
	targets=(10.10.1.1 10.10.1.2 10.10.2.2 10.10.2.1)
	for t in ${targets[@]}; do
	    exec_ns ${entity_nss[0]} ping -qc 1 -W 1 $t
	done
	exec_ns ${entity_nss[0]} ping -qc 1 -W 1 $aux_srv_addr || echo "OK: acl denies to 10.10.2.3."
	;;
    pong)
	targets=(10.10.1.1 10.10.1.2 10.10.2.2 10.10.2.1)
	for t in ${targets[@]}; do
	    exec_ns ${entity_nss[1]} ping -qc 1 -W 1 $t
	done
	;;
    pings)
	while true; do
	    exec_ns ${entity_nss[0]} nping --tcp 10.10.2.2 -c 20 --delay 0.1
	    sleep 10
	done
	;;
    *)
	usage
	rc=1
	;;
esac
exit $rc
