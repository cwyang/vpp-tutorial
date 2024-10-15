#!/bin/bash
#set -e
ip='sudo ip'


function prepare_nic {
    local ns1="$1"; shift
    local eth1="$1"; shift
    local ip1="$1"; shift
    local ns2="$1"; shift
    local eth2="$1"; shift
    local ip2="$1"; shift
    $ip netns del $ns1
    $ip netns del $ns2
    $ip netns add $ns1
    $ip netns add $ns2
    $ip link add name $eth1 type veth peer name $eth2

    $ip link set $eth1 netns $ns1
    $ip netns exec $ns1 ip link set dev $eth1 up
    $ip netns exec $ns1 ip addr add $ip1 broadcast 10.100.0.255 dev $eth1
    $ip netns exec $ns1 ip route add default via 10.100.0.2 dev $eth1

    $ip link set $eth2 netns $ns2
    $ip netns exec $ns2 ip link set dev $eth2 up
    $ip netns exec $ns2 ip addr add $ip2 broadcast 10.100.0.255 dev $eth2
    
}

prepare_nic test veth0 10.100.0.1/24 test2 veth1 10.100.0.2/24
