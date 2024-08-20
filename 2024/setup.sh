#!/bin/bash
#set -e
vppctl='sudo vppctl'
ip='sudo ip'

function prepare_nic {
    local ns="$1"; shift
    local ipaddr="$1"; shift
    local broadcast="$1"; shift
    local gw="$1"; shift
    $ip netns del $ns
    $ip netns add $ns
    $ip link del $ns-vpp
    $ip link del $ns-host
    $ip link add name $ns-vpp type veth peer name $ns-host
    $ip link set $ns-host netns $ns
    $ip link set dev $ns-host up
    $ip netns exec $ns ip link set dev $ns-host up
    $ip netns exec $ns ip addr add $ipaddr broadcast $broadcast dev $ns-host
    $ip netns exec $ns ip route add default via $gw dev $ns-host

}

function setup_host {
    prepare_nic svr 10.10.1.1/24 10.10.1.255 10.10.1.2
    prepare_nic span 10.20.1.1/24 10.20.1.255 10.20.1.2
    # gre 잘안돼
    #$ip netns exec span ip tunnel add gre1 mode gre remote 10.20.1.2 local 10.20.1.1
    #$ip netns exec span ip addr add 192.168.100.1/32 dev gre1
    #$ip netns exec span ip link set gre1 up
    # erspan 잘안돼
    # https://developers.redhat.com/blog/2019/05/17/an-introduction-to-linux-virtual-interfaces-tunnels#erspan_and_ip6erspan
    #$ip netns exec span ip link add dev erspan1 type erspan local 10.20.1.1 remote 10.20.1.2 seq key 1 erspan_ver 1 erspan 1
    #$ip netns exec span ip addr add 192.168.100.1/32 dev erspan1
    #$ip netns exec span ip link set erspan1[ up
}

function setup_vpp {
    $vppctl set inter state GigabitEthernet0/4/0 up
    $vppctl set inter ip address GigabitEthernet0/4/0 192.168.0.50/24

    $vppctl create host-interface name svr-vpp
    $vppctl set int state host-svr-vpp up
    $vppctl set int ip address host-svr-vpp 10.10.1.2/24
    $vppctl create host-interface name span-vpp
    $vppctl set int state host-span-vpp up
    $vppctl set int ip address host-span-vpp 10.20.1.2/24

    $vppctl nat44 plugin enable
    $vppctl nat44 forwarding enable
    #$vppctl nat44 add address 192.168.0.50
    $vppctl set interface nat44 in host-svr-vpp out GigabitEthernet0/4/0
    $vppctl nat44 add static mapping tcp local 10.10.1.1 8000 external 192.168.0.50 8000  # 10.10.1.1!

    #$vppctl ip table add 1
    #뒤에 erspan 1을 떼면 통신이 안됨. erspan의 의미?
    #gre span과 erspan의 차이
    #$vppctl create gre tunnel src 10.20.1.2 dst 10.20.1.1 instance 1 outer-table-id 0 erspan 1
    #$vppctl set inter ip addr gre1 192.168.100.2/32
    #$vppctl set inter state gre1 up
    #$vppctl set inter span host-svr-vpp destination gre1
    #$vppctl show gre tunnel
    #$vppctl show inter span
}

setup_host
setup_vpp
