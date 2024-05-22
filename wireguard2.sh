#!/bin/bash
#
# 21 May 2024
# Chul-Woong Yang
#
# 테스트 환경
#
#  VPP1 (C)         VPP2 (S)
#   wg0              wg0
#     |               |       
#     +---------------+       

# exit on error
set -e
trap 'echo line $LINENO exits with code $?.' ERR

vpp_conf=$(cat <<EOF
unix {
    nodaemon
    cli-listen /run/vpp/cli.sock
    cli-no-pager
    full-coredump
}
plugins {
    plugin dpdk_plugin.so {
        disable
    }
}
socksvr {
        socket-name /run/vpp/api.sock
}
statseg {
        socket-name /run/vpp/stats.sock
    per-node-counters on
}
EOF
	)

debug=0
echo=""
vpp=vpp
ip="ip"
raw_ip=$ip
vppctl1="sudo vppctl -s /run/vpp/cli1.sock"
vppctl2="sudo vppctl -s /run/vpp/cli2.sock"
if [ "$debug" -ne 0 ]; then
    vppctl="echo $vppctl"
    echo="echo"
fi
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
    ip_ns $ns link add veth1 type veth peer name veth2
    ip_ns $ns link set lo up
    ip_ns $ns link set veth1 up
    ip_ns $ns link set veth2 up
}
function run_vpp {
    local id="$1"; shift
    local addr="$1"; shift
    local gw="$1"; shift
    local privaddr="$1"; shift
    local wgaddr="$1"; shift
    local peeraddr="$1"; shift
    local peerwgaddr="$1"; shift
    local myprvkey="$1"; shift
    local peerpubkey="$1"; shift
    local port=55555

    local vppctl

    if [ "$id" -eq 1 ]; then
	vppctl=$vppctl1
    else
	vppctl=$vppctl2
    fi
    echo "$id $addr $gw"
    sleep 1
    exec_ns test $vpp -c min$id.conf
    sleep 1
    echo "runvpp 2"
    $vppctl create host-interface name veth$id
    $vppctl set interface ip address host-veth$id $addr/24
    $vppctl set interface ip address host-veth$id $privaddr/32
    $vppctl set interface state host-veth$id up
    $vppctl wireguard create listen-port $port \
	    private-key $myprvkey src $addr
    $vppctl set interface state wg0 up
    $vppctl set interface ip address wg0 $wgaddr/32
    $vppctl wireguard peer add wg0 \
	    public-key $peerpubkey \
	    endpoint $peeraddr allowed-ip 0.0.0.0/0 dst-port $port

    $vppctl ip route add 0.0.0.0/0 via $gw
    $vppctl ip route add $privaddr/24 via $peerwgaddr wg0
}

function usage {
    echo "Usage: $0 {ns|vpp}"
}
rc=255
case "$1" in
    ns|netns)
	make_ns test
	;;
    vpp)
	pkill vpp || true
	run_vpp 1 172.17.0.2 172.17.0.1 192.168.0.2 10.1.0.2 172.17.0.3 10.1.0.3 \
		oNWegnCt9QIQ7ik3fCqlKXsY9M6OZpqyJtR6A7a0wHY= \
		3i1WMY6eCIYEX1djjCtLHLU7zqsSDH85r52KrznsxAc=

	run_vpp 2 172.17.0.3 172.17.0.1 192.168.0.3 10.1.0.3 172.17.0.2 10.1.0.2 \
		SBCMKqPqmc0PivhTyZmiXy1hJgF3sbQu/b/5gVDeoFM= \
		5E8ynZHX31vER1CE2FAxTP944h6pxsb6ely5eCmaXEc=
	;;
    
    ping)
	$vppctl2 clear trace
	$vppctl2 trace add af-packet-input 10
	$vppctl1 ping 192.168.0.3 source host-veth1
	$vppctl2 show trace
	;;
    *)
	usage
	rc=1
	;;
esac
exit $rc
