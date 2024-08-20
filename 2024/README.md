# Another Progressive VPP Tutorial

# Mars
```
ubuntu@mars:~$ ip addr
...
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether fa:16:3e:a7:a4:f4 brd ff:ff:ff:ff:ff:ff
    altname enp0s3
    altname ens3
    inet 192.168.0.57/24 metric 100 brd 192.168.0.255 scope global dynamic eth0
       valid_lft 104sec preferred_lft 104sec
    inet6 fe80::f816:3eff:fea7:a4f4/64 scope link
       valid_lft forever preferred_lft forever
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether fa:16:3e:4b:c0:8f brd ff:ff:ff:ff:ff:ff
    altname enp0s4
    altname ens4
    inet 192.168.0.50/24 metric 200 brd 192.168.0.255 scope global dynamic eth1
       valid_lft 103sec preferred_lft 103sec
    inet6 fe80::f816:3eff:fe4b:c08f/64 scope link
       valid_lft forever preferred_lft forever
```

# VPP
```
cat vpp.conf
ubuntu@mars:~/vpp-tutorial/2024$ cat vpp.conf
unix {
        cli-listen /run/vpp/cli.sock
        log /var/log/vpp/vpp.log
}
logging {
        default-log-level info
        default-syslog-log-level info
}
plugins {
        plugin dpdk_plugin.so { disable }
}

ubuntu@mars$ sudo vppctl show version
vpp v22.10.0-135~gb08fbe84e built by ubuntu on mars
```

# Creating an DPDK Interface

## ping from moon
```
ubuntu@moon:~$ ping 192.168.0.50
PING 192.168.0.50 (192.168.0.50) 56(84) bytes of data.
64 bytes from 192.168.0.50: icmp_seq=1 ttl=64 time=1.53 ms
```
## attaching a dpdk interface
```
ubuntu@mars$ ethtool -i eth1 |grep bus
bus-info: 0000:00:04.0

ubuntu@mars$ cat >> vpp.conf
plugins {
	plugin nat_plugin.so { enable }
}
dpdk {
        dev 0000:00:04.0
}
(and remove dpdk plugin disable part)

ubuntu@mars$ sudo ifconfig eth1 down

ubuntu@mars$ sudo vpp -c vpp.conf

DBGvpp# set inter state GigabitEthernet0/4/0 up
DBGvpp# set inter ip address GigabitEthernet0/4/0 192.168.0.50/24
DBGvpp# show inter address
GigabitEthernet0/4/0 (up):
  L3 192.168.0.50/24
local0 (dn):


DBGvpp# show hardware-interfaces
              Name                Idx   Link  Hardware
GigabitEthernet0/4/0               1     up   GigabitEthernet0/4/0
  Link speed: unknown
  RX Queues:
    queue thread         mode
    0     main (0)       polling
  TX Queues:
    TX Hash: [name: hash-eth-l34 priority: 50 description: Hash ethernet L34 headers]
    queue shared thread(s)
    0     no     0
  Ethernet address fa:16:3e:4b:c0:8f
  Red Hat Virtio
    carrier up full duplex max-frame-size 9022
    flags: admin-up maybe-multiseg tx-offload int-supported
    Devargs:
    rx: queues 1 (max 8), desc 256 (min 32 max 32768 align 1)
    tx: queues 1 (max 8), desc 256 (min 32 max 32768 align 1)
    pci: device 1af4:1000 subsystem 1af4:0001 address 0000:00:04.00 numa 0
    max rx packet len: 9728
    promiscuous: unicast off all-multicast on
    vlan offload: strip off filter off qinq off
    rx offload avail:  vlan-strip udp-cksum tcp-cksum tcp-lro vlan-filter
                       scatter
    rx offload active: scatter
    tx offload avail:  vlan-insert udp-cksum tcp-cksum tcp-tso multi-segs
    tx offload active: udp-cksum tcp-cksum multi-segs
    rss avail:         none
    rss active:        none
    tx burst function: (not available)
    rx burst function: (not available)

local0                             0    down  local0
  Link speed: unknown
  local
```

## ping from moon again
```
ubuntu@moon:~$ ping 192.168.0.50
PING 192.168.0.50 (192.168.0.50) 56(84) bytes of data.
64 bytes from 192.168.0.50: icmp_seq=2 ttl=64 time=1.04 ms
64 bytes from 192.168.0.50: icmp_seq=3 ttl=64 time=0.972 ms

DBGvpp# show inter GigabitEthernet0/4/0
              Name               Idx    State  MTU (L3/IP4/IP6/MPLS)     Counter          Count
GigabitEthernet0/4/0              1      up          9000/0/0/0     rx packets                     4
                                                                    rx bytes                     336
                                                                    tx packets                     3
                                                                    tx bytes                     238
                                                                    drops                          1
                                                                    ip4                            3
DBGvpp# show error
   Count                  Node                              Reason               Severity
         1             arp-reply             ARP request IP4 source address lear   info
         1             ip4-glean                      ARP requests sent            info
         3           ip4-icmp-input                   echo replies sent            info
```

# Running web server
```
ubuntu@mars$ python -V
Python 3.10.12
ubuntu@mars$ python -m http.server 8000
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...

# web server is only bound to eth0
ubuntu@moon:~$ curl -q -o /dev/null http://192.168.0.57:8000
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   463  100   463    0     0  22721      0 --:--:-- --:--:-- --:--:-- 23150
ubuntu@moon:~$ curl -q -o /dev/null http://192.168.0.50:8000
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:--  0:00:01 --:--:--     0^C
```

# Put web server inside NAT
```
[@VPP vpp(192.168.0.50) -- svr-vpp(10.10.1.2/24)] -- [@svr-netns svr-host(10.10.1.1/24) -- web-server]

ubuntu@mars$ ./setup.sh # NAT setup


ubuntu@moon:~$ curl -q -o /dev/null http://192.168.0.50:8000

DBGvpp# show int addr
GigabitEthernet0/4/0 (up):
  L3 192.168.0.50/24
host-span-vpp (up):
  L3 10.20.1.2/24
host-svr-vpp (up):
  L3 10.10.1.2/24
local0 (dn):

root@mars# ip netns exec test python -m http.server 8000
Serving HTTP on :: port 8000 (http://[::]:8000/) ...
...
ubuntu@moon:~$ curl -q -o /dev/null http://192.168.0.50:8000
...
```

# ERSPAN
```
[@VPP vpp(192.168.0.50) -- svr-vpp(10.10.1.2/24) ] -- [@svr-netns  svr-host(10.10.1.1/24)  -- web-server]
                           |
						   +- span-vpp(10.20.1.2/24) -- [@span-netns span-host(10.20.1.1/24)]

comment create gre tunnel src <addr> dst <addr> [instance <n>]
	[outer-fib-id <fib>] [teb | erspan <session-id>] [del] [multipoint]

ip table add 1
DBGvpp# create gre tunnel src 10.20.1.2 dst 10.20.1.1 instance 1 outer-table-id 1 erspan 1
gre0
DBGvpp# show gre tunnel
[0] instance 0 src 10.20.1.2 dst 10.20.1.1 fib-idx 0 sw-if-idx 4 payload L3 point-to-point
DBGvpp# set inter state gre1 up
set interface span host-svr-vpp destination gre1

se


set interface erspan <source-interface> destination <destination-ip> session-id <session-id>
]
```
