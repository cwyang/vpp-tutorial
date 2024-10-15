#!/bin/bash
#
# 8 Aug 2022
# Chul-Woong Yang
#
# 테스트 환경
# client network: 10.10.1.0/24 netns client
# server network: 10.10.2.0/24 netns server
#
# Master)
#  Client (C)    ======= ROUTER (R) =======    SERVER (S)
# 10.10.1.2/24   10.10.1.1/24  10.10.2.1/24   10.10.2.2/24, 10.10.2.3/32
#   veth0        client-veth0  server-veth0       veth0
#     |               |              |              |
#     +---------------+              +--------------+
# netns client          netns router          netns server
#
# Backup)
# 10.20.1.2/24 - 10.20.1.1/24  10.20.2.1/24   10.20.2.2/24
#
# vpp1 (10.100.1.1/24) --memif-- vpp2 (10.100.1.2/24)
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
nsr="router"
nss="server"
entity_nss=($nsc $nss)
entity_nets=("10.10.1.0/24" "10.10.2.0/24")
entity_addrs=("10.10.1.2/24" "10.10.2.2/24")
router_addrs=("10.10.1.1/24" "10.10.2.1/24")
entity2_nets=("10.20.1.0/24" "10.20.2.0/24")
entity2_addrs=("10.20.1.2/24" "10.20.2.2/24")
router2_addrs=("10.20.1.1/24" "10.20.2.1/24")
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
    local peer_host=${peer_addr%/*}	# remove mask
    local route_dest="$1"; shift

    #echo "make vethpair: $nic_name $ns $peer_ns $addr $peer_addr $route_dest"
    $ip link add $nic_name type veth peer name $ns-$nic_name
    $ip link set $nic_name netns $ns
    $ip link set $ns-$nic_name netns $peer_ns
    # my addr
    ip_ns $ns addr add $addr dev $nic_name
    ip_ns $ns link set $nic_name up
    # and default route
    ip_ns $ns route add $route_dest via $peer_host dev $nic_name
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
    local nets=($1 $2); shift 2
    local addrs=($1 $2); shift 2
    local routers=($1 $2); shift 2
    local nic="$1"; shift
    for i in ${!entity_nss[@]}; do
echo	vppctl_with $id create host-interface name ${entity_nss[i]}-$nic #num-rx-queues 2 num-tx-queues 2
	vppctl_with $id create host-interface name ${entity_nss[i]}-$nic #num-rx-queues 2 num-tx-queues 2
	vppctl_with $id set interface ip address host-${entity_nss[i]}-$nic ${routers[i]}
	vppctl_with $id set interface state host-${entity_nss[i]}-$nic up
	# add routing
	vppctl_with $id ip route add ${nets[i]} via ${addrs[i]%/*}
	echo ${entity_nss[i]}-$nic done
    done
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
	make_vethpair ${nic_names[0]} $nsc $nsr ${entity_addrs[0]} ${router_addrs[0]} default
	make_vethpair ${nic_names[0]} $nss $nsr ${entity_addrs[1]} ${router_addrs[1]} default
	make_vethpair ${nic_names[1]} $nsc $nsr ${entity2_addrs[0]} ${router2_addrs[0]} ${entity2_nets[1]}
	make_vethpair ${nic_names[1]} $nss $nsr ${entity2_addrs[1]} ${router2_addrs[1]} ${entity2_nets[0]}
	# server additional address
	ip_ns $nss addr add $aux_srv_addr dev ${nic_names[0]}
	;;
    gdb)
	exec_ns $nsr pkill vpp || true
	(cd /home/vagrant/vpp-dev; exec_ns $nsr make debug)
	;;
    vpp)
	#exec_ns $nsr pkill vpp || true
	#exec_ns $nsr $vpp -c $vppconf
	sleep 1
	create_vpp_interface vpp1 ${entity_nets[@]} ${entity_addrs[@]} ${router_addrs[@]} ${nic_names[0]}
	create_vpp_interface vpp2 ${entity2_nets[@]} ${entity2_addrs[@]} ${router2_addrs[@]} ${nic_names[1]}
	for i in ${!router_ids[@]}; do
	id=${router_ids[$i]}
	# sample acl rule
	vppctl_with $id ip route add ${aux_srv_addr}/32 via ${entity_addrs[1]%/*}
	targets=(10.10.1.1 10.10.1.2 10.10.2.2 10.10.2.1)
	rule=""
	rule1=""
	for t in ${targets[@]}; do
	    #rule="$rule permit+reflect proto 6 dst $t/32," # icmp
	    rule="$rule permit+reflect proto 6 dst $t/32 desc {$t}," # icmp
	    #rule="$rule permit proto 6 dst $t/32 desc {$t}," # icmp
	    rule1="$rule1 deny proto 6 src $t/32 desc {hmm-$t}," # icmp
	done
	rule=${rule%,}
	rule1=${rule1%,}
	echo vppctl_with $id set acl-plugin acl $rule
	vppctl_with $id set acl-plugin acl $rule tag example_permit_0
	vppctl_with $id set acl-plugin acl $rule1 tag example_permit_1
	vppctl_with $id set acl-plugin acl deny # tag example_deny_0
	#$vppctl set acl-plugin acl permit # tag example_deny_0
	vppctl_with $id set acl-plugin interface host-${entity_nss[0]}-${nic_names[$i]} input acl 0
	vppctl_with $id set acl-plugin interface host-${entity_nss[0]}-${nic_names[$i]} input acl 2
	vppctl_with $id set acl-plugin interface host-${entity_nss[0]}-${nic_names[$i]} output acl 0
	vppctl_with $id set acl-plugin interface host-${entity_nss[0]}-${nic_names[$i]} output acl 2
	vppctl_with $id show acl-plugin interface sw_if_index 1 acl
	done
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
	    rule="$rule permit+reflect proto 6 dst $t/32," # icmp
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
    *)
	usage
	rc=1
	;;
esac
exit $rc
