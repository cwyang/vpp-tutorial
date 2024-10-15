#!/bin/bash
#set -e
vppctl='sudo vppctl'
ip='sudo ip'

tunnel_mode="vxlan" # [ gre | erspan | vxlan ], gre does not work
tunnel_id="100"
server_ip="192.168.0.50"
vip="192.168.0.51"
nat_nic="GigabitEthernet0/4/0"

function prepare_nic {
    local ns="$1"; shift
    local ipaddr="$1"; shift
    local broadcast="$1"; shift
    local gw="$1"; shift
    $ip netns del $ns
    $ip netns add $ns
    $ip link del $ns-vpp &> /dev/null
    $ip link del $ns-host &> /dev/null
    $ip link add name $ns-vpp type veth peer name $ns-host
    $ip link set $ns-host netns $ns
    $ip netns exec $ns ip link set dev $ns-host up
    $ip netns exec $ns ip addr add $ipaddr broadcast $broadcast dev $ns-host
    $ip netns exec $ns ip route add default via $gw dev $ns-host
}

function setup_tunnel {
    # https://developers.redhat.com/blog/2019/05/17/an-introduction-to-linux-virtual-interfaces-tunnels#erspan_and_ip6erspan
    local type="${1:-gre}"; shift
    local nic="${type}1"
    local physnic="span-host"
    
    if [ "$type" = "erspan" ]; then
	$ip netns exec span ip link add dev $nic type $type remote 10.20.1.2 local 10.20.1.1 erspan_ver 1 erspan 1 seq key $tunnel_id
    elif [ "$type" = "vxlan" ]; then
	$ip netns exec span ip link add $nic type $type dev $physnic remote 10.20.1.2 local 10.20.1.1 dstport 4789 id $tunnel_id
    else
	$ip netns exec span ip tunnel add $nic mode $type remote 10.20.1.2 local 10.20.1.1
	#$ip netns exec span ip link add dev $nic type $type remote 10.20.1.2 local 10.20.1.1
    fi
    $ip netns exec span ip addr add 192.168.100.1/32 dev $nic
    $ip netns exec span ip link set $nic up
}

function setup_host {
    prepare_nic svr 10.10.1.1/24 10.10.1.255 10.10.1.2
    prepare_nic span 10.20.1.1/24 10.20.1.255 10.20.1.2
    
    # gre / erspan
    setup_tunnel $tunnel_mode
}

function setup_vpp_tunnel {
    local type="${1:-gre}"; shift
    local nic="gre1"

    if [ "$type" = "vxlan" ]; then
	$vppctl create vxlan tunnel src 10.20.1.2 dst 10.20.1.1 instance 1 vni $tunnel_id
	nic="vxlan_tunnel1"
    elif [ "$type" = "erspan" ]; then
	$vppctl create gre tunnel src 10.20.1.2 dst 10.20.1.1 instance 1 outer-table-id 0 erspan $tunnel_id
    else
	$vppctl create gre tunnel src 10.20.1.2 dst 10.20.1.1 instance 1 outer-table-id 0
    fi

    $vppctl set inter ip addr $nic 192.168.100.2/32
    $vppctl set inter state $nic up
    $vppctl set inter span host-svr-vpp destination $nic
    #$vppctl show gre tunnel
    #$vppctl show inter span
}

function setup_vpp {
    $vppctl set inter state $nat_nic up
    $vppctl set inter ip address $nat_nic $server_ip/24 # 192.168.0.50
    $vppctl ip route 0.0.0.0/0 via 192.168.0.1 # gw

    # vip에 대한 arp response를 위해 nat_nic의 보안기능을 콘솔에서 off해야한다.
    
    $vppctl vrrp vr add $nat_nic vr_id 1 priority 101 interval 1000 hw_mac $vip # 192.168.0.51
    $vppctl vrrp proto start vr_id 1 $nat_nic
    #$vppctl show vrrp vr
    
    local ifs=(svr-vpp span-vpp)
    local ips=(10.10.1.2/24 10.20.1.2/24)
    for i in ${!ifs[@]}; do
	$vppctl create host-interface name ${ifs[$i]}
	$vppctl set int state host-${ifs[$i]} up
	$vppctl set int ip address host-${ifs[$i]} ${ips[$i]}
    done

    $vppctl nat44 plugin enable sessions 10000
    $vppctl set interface nat44 in host-svr-vpp out $nat_nic # output-feature is needed?
    $vppctl nat44 add static mapping tcp local 10.10.1.1 external $server_ip
    $vppctl nat44 add address $server_ip

    $vppctl trace add af-packet-input 100
    #$vppctl nat44 forwarding enable
    
    return

    # gre / erspan
    setup_vpp_tunnel $tunnel_mode

    # should ping from vpp to gw
    # ping 192.168.0.1
    # SNAT: should curl from svr to outer (moon)
    # ip netns exec svr curl 133.186.163.55
    # DNAT: should curl/ping from outer to VIP
    # moon# curl 133.186.163.64
    # moon# ping 133.186.163.64
    
}
 

setup_host
setup_vpp

exit 0

## span destination을 (non erspan) gre tunnel로 지정하면 아래에서 죽는다
Aug 20 22:19:14 mars vnet[27897]: /home/ubuntu/vpp-dev/src/vnet/adj/adj.h:462 (adj_get) assertion `! pool_is_free (adj_pool, _e)' fails
Aug 20 22:19:14 mars vnet[27897]: received signal SIGABRT, PC 0x7f4fa21ab9fc
Aug 20 22:19:14 mars vnet[27897]: #0  0x00007f4fa25e5e5c unix_signal_handler + 0x1ec
Aug 20 22:19:14 mars vnet[27897]: #1  0x00007f4fa2157520 0x7f4fa2157520
Aug 20 22:19:14 mars vnet[27897]: #2  0x00007f4fa21ab9fc pthread_kill + 0x12c
Aug 20 22:19:14 mars vnet[27897]: #3  0x00007f4fa2157476 raise + 0x16
Aug 20 22:19:14 mars vnet[27897]: #4  0x00007f4fa213d7f3 abort + 0xd3
Aug 20 22:19:14 mars vnet[27897]: #5  0x000055a3bd2840a3 0x55a3bd2840a3
Aug 20 22:19:14 mars vnet[27897]: #6  0x00007f4fa24545c9 debugger + 0x9
Aug 20 22:19:14 mars vnet[27897]: #7  0x00007f4fa2454380 _clib_error + 0x210
Aug 20 22:19:14 mars vnet[27897]: #8  0x00007f4fa2fd1cee adj_get + 0x8e
Aug 20 22:19:14 mars vnet[27897]: #9  0x00007f4fa2fd175f adj_l2_rewrite_inline + 0x14f
Aug 20 22:19:14 mars vnet[27897]: #10 0x00007f4fa2fd1ade adj_l2_midchain_node_fn_hsw + 0x5e
Aug 20 22:19:14 mars vnet[27897]: #11 0x00007f4fa258aaa2 dispatch_node + 0x322
Aug 20 22:19:14 mars vnet[27897]: #12 0x00007f4fa258b4c2 dispatch_pending_node + 0x3b2
Aug 20 22:19:14 mars vnet[27897]: #13 0x00007f4fa25869e8 vlib_main_or_worker_loop + 0x898
Aug 20 22:19:14 mars vnet[27897]: #14 0x00007f4fa258822a vlib_main_loop + 0x1a
