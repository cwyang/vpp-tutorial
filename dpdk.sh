#!/bin/bash
#
# 28 Mar 2025
# Chul-Woong Yang
function usage {
    echo "Usage: $0 {load|reset|unbind}"
}

DEVBIND=/usr/local/bin/dpdk-devbind.py
ETH_DPDK=eth1
PCIBUS=0000:00:04.0
VPPCTL="sudo vppctl"

rc=255
case "$1" in
    
    load)
	$VPPCTL set inter state GigabitEthernet0/4/0 up
	$VPPCTL set inter ip address GigabitEthernet0/4/0 192.168.0.54/24
	$VPPCTL show inter address
	$VPPCTL show hardware-interfaces  # mac is same to kernel mac
	;;
    reset)
	$DEVBIND -s
	echo 'unbind & rebind PCI $PCIBUS to kernel'
	sudo $DEVBIND -u $PCIBUS
	sudo $DEVBIND -b virtio-pci $PCIBUS
	$DEVBIND -s
	;;
    unbind)
	sudo ifconfig $ETH_DPDK down
	sudo $DEVBIND -u $PCIBUS
	$DEVBIND -s
	;;
    *)
	usage
	rc=1
	;;
esac
exit $rc
