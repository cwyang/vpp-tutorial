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
vppctl1="docker exec -it vpp1 vppctl -s /run/vpp/cli.sock"
vppctl2="docker exec -it vpp2 vppctl -s /run/vpp/cli.sock"
if [ "$debug" -ne 0 ]; then
    vppctl="echo $vppctl"
    echo="echo"
fi
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

    local vppctl="docker exec -it vpp$id vppctl -s /run/vpp/cli.sock"

    echo "$id $addr $gw"
    $echo docker stop vpp$id || true
    sleep 1
    temp_file=$(mktemp)
    printf "$vpp_conf" >> $temp_file
    $echo docker run -it --detach --rm --name vpp$id -v $temp_file:/etc/vpp/vpp.conf \
	  --privileged ligato/vpp-agent /usr/bin/vpp -c /etc/vpp/vpp.conf
    sleep 1
    $vppctl create host-interface name eth0
    $vppctl set interface ip address host-eth0 $addr/24
    $vppctl set interface ip address host-eth0 $privaddr/32
    $vppctl set interface state host-eth0 up
    $vppctl wireguard create listen-port $port \
	    private-key $myprvkey src $addr
    $vppctl set interface state wg0 up
    $vppctl set interface ip address wg0 $wgaddr/32
    $vppctl wireguard peer add wg0 \
	    public-key $peerpubkey \
	    endpoint $peeraddr allowed-ip 0.0.0.0/0 dst-port $port

    $vppctl ip route add 0.0.0.0/0 via $gw
    $vppctl ip route add $privaddr/24 via $peerwgaddr wg0

    rm $temp_file
}

function usage {
    echo "Usage: $0 {vpp}"
}
rc=255
case "$1" in
    vpp)
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
	$vppctl1 ping 192.168.0.3 source host-eth0
	$vppctl2 show trace
	;;
    *)
	usage
	rc=1
	;;
esac
exit $rc
