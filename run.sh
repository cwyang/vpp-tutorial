#!/bin/bash
#
# 8 Aug 2022
# Chul-Woong Yang
#
# 테스트 환경
# client network: 10.10.1.0/24 netns client
# server network: 10.10.2.0/24 netns server
#
#  Client (C)    ======= ROUTER (R) =======    SERVER (S)
# 10.10.1.2/24   10.10.1.1/24  10.10.2.1/24   10.10.2.2/24, 10.10.2.3/32
#   veth0        client-veth0  server-veth0       veth0
#     |               |              |              |
#     +---------------+              +--------------+
# netns client          netns router          netns server

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
nic_name="veth0"
nsc="client"
nsr="router"
nss="server"
entity_nss=($nsc $nss)
entity_nets=("10.10.1.0/24" "10.10.2.0/24")
entity_addrs=("10.10.1.2/24" "10.10.2.2/24")
router_addrs=("10.10.1.1/24" "10.10.2.1/24")
aux_srv_addr="10.10.2.3"

function exec_ns {
    local ns="$1"; shift
    $echo sudo $raw_ip netns exec $ns $@
}
function ip_ns {
    local ns="$1"; shift
    exec_ns $ns $raw_ip $@
}
function make_ns {
    local ns="$1"; shift
    $ip netns del $ns || true # ignore non-existing ns deletion
    $ip netns add $ns
    ip_ns $ns link set lo up
}

function make_vethpair {
    local ns="$1"; shift
    local peer_ns="$1"; shift
    local addr="$1"; shift
    local peer_addr="$1"; shift
    local peer_host=${peer_addr%/*}	# remove mask

    $ip link add $nic_name type veth peer name $ns-$nic_name
    $ip link set $nic_name netns $ns
    $ip link set $ns-$nic_name netns $peer_ns
    # my addr
    ip_ns $ns addr add $addr dev $nic_name
    ip_ns $ns link set $nic_name up
    # and default route
    ip_ns $ns route add default via $peer_host dev $nic_name
    exec_ns $ns sysctl -qw net.ipv4.ip_forward=1
}

function dns_setup {
    local ns="$1"; shift
    path=/etc/netns/$ns
    mkdir -m 644 -p $path
    echo "nameserver 8.8.8.8" > $path/resolv.conf
}

function usage {
    echo "Usage: $0 {netns|vpp|ping|pong}"
}
rc=255
case "$1" in
    ns|netns)
	for ns in $nsc $nsr $nss; do
	    make_ns $ns
	    $echo dns_setup $ns
	done
	make_vethpair $nsc $nsr ${entity_addrs[0]} ${router_addrs[0]}
	make_vethpair $nss $nsr ${entity_addrs[1]} ${router_addrs[1]}
	# server additional address
	ip_ns $nss addr add $aux_srv_addr dev $nic_name
	;;
    vpp)
	exec_ns $nsr pkill vpp || true
	exec_ns $nsr $vpp -c $vppconf
	sleep 1
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
	    rule="$rule proto 1 dst $t/32," # icmp
	done
	rule=${rule%,}
	echo $vppctl set acl-plugin acl permit $rule
	$vppctl set acl-plugin acl permit $rule
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
    *)
	usage
	rc=1
	;;
esac
exit $rc
