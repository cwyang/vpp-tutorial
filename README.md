# vpp-tutorial

https://fd.io/docs/vpp/master/gettingstarted/progressivevpp/settingupenvironment.html#install-virtual-box-and-vagrant

## Running Vagrant
* [Vagrantfile](Vagrantfile)
```console
$ vagrant up
$ vagrant ssh
$ sudo bash
# apt-get update
# reboot -n
$ vagrant ssh
```

## Install VPP
```console
$ sudo bash
# echo "deb [trusted=yes] https://packagecloud.io/fdio/release/ubuntu bionic main" > /etc/apt/sources.list.d/99fd.io.list
# curl -L https://packagecloud.io/fdio/release/gpgkey | sudo apt-key add -
# apt-get update
# apt-get install vpp vpp-plugin-core vpp-plugin-dpdk
# service vpp stop      ; we'll be creating our own instances of VPP
```

## VPP startup file
* path: `/etc/vpp/`
```text
# startup1.conf
unix { nodaemon cli-listen /run/vpp/cli-vpp1.sock}
api-segment { prefix vpp1 }
plugins { plugin dpdk_plugin.so { disable } }
# startup2.conf
unix { nodaemon cli-listen /run/vpp/cli-vpp2.sock}
api-segment { prefix vpp2 }
plugins { plugin dpdk_plugin.so { disable } }
```

## Running VPP
```console
root@vagrant:~# /usr/bin/vpp -c /etc/vpp/startup1.conf
root@vagrant:~# tail -1 /var/log/syslog
Feb 16 11:38:21 vagrant /usr/bin/vpp[1895]: vat-plug/load: vat_plugin_register: oddbuf plugin not loaded...
```

Let's `vppctl`
```console
root@vagrant:~# vppctl -s /run/vpp/cli-vpp1.sock
root@vagrant:~# vppctl -s /run/vpp/cli-vpp1.sock
   _______    _        _   _____  ___
__/ __/ _ \  (_)__    | | / / _ \/ _ \
_/ _// // / / / _ \   | |/ / ___/ ___/
/_/ /____(_)_/\___/   |___/_/  /_/

vpp# show version
show version
vpp v21.01-release built by root on fcb1bae62b24 at 2021-01-27T16:06:22
```
## Play with Interface

1. Create veth interfaces on host and turn up both ends
```
$ sudo ip link add name vpp1out type veth peer name vpp1host
$ sudo ip link set dev vpp1out up
$ sudo ip link set dev vpp1host up
$ ip link
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP mode DEFAULT group default qlen 1000
        link/ether 08:00:27:a9:d0:cb brd ff:ff:ff:ff:ff:ff
        3: vpp1host@vpp1out: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default qlen 1000
            link/ether 16:1d:6c:36:33:7e brd ff:ff:ff:ff:ff:ff
            4: vpp1out@vpp1host: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default qlen 1000
                link/ether f2:07:99:61:3b:de brd ff:ff:ff:ff:ff:ff
```
2. Assign an IP address
```
$ sudo ip addr add 10.10.1.1/24 dev vpp1host
$ ip addr show vpp1host
3: vpp1host@vpp1out: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 16:1d:6c:36:33:7e brd ff:ff:ff:ff:ff:ff
    inet 10.10.1.1/24 scope global vpp1host
       valid_lft forever preferred_lft forever
```
3. Create vpp host-interface
```
vpp# sh hardware
sh hardware
              Name                Idx   Link  Hardware
local0                             0    down  local0
  Link speed: unknown
  local
vpp# create host-interface name vpp1out
create host-interface name vpp1out
host-vpp1out
vpp# sh hardware
sh hardware
              Name                Idx   Link  Hardware
host-vpp1out                       1     up   host-vpp1out
  Link speed: unknown
  Ethernet address 02:fe:06:c9:89:07
  Linux PACKET socket interface
local0                             0    down  local0
  Link speed: unknown
  local
vpp# set int state host-vpp1out up
set int state host-vpp1out up
vpp# show int
show int
              Name               Idx    State  MTU (L3/IP4/IP6/MPLS)     Counter          Count
host-vpp1out                      1      up          9000/0/0/0
local0                            0     down          0/0/0/0
vpp# set int ip address host-vpp1out 10.10.1.2/24
set int ip address host-vpp1out 10.10.1.2/24
vpp# show int addr
show int addr
host-vpp1out (up):
  L3 10.10.1.2/24
local0 (dn):
```
4. Using the `trace` command
  * `show trace`
  * `clear trace`
  * `trace filter [include NODE COUNT | exclude NODE COUNT | none]`
  * `trace add [type] [num]`, ex) `trace add af-packet-input 10`

```
vpp# trace add af-packet-input 10
trace add af-packet-input 10
vpp# q
q

$ ping -c 1 10.10.1.2
PING 10.10.1.2 (10.10.1.2) 56(84) bytes of data.
64 bytes from 10.10.1.2: icmp_seq=1 ttl=64 time=1.00 ms
--- 10.10.1.2 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 1.001/1.001/1.001/0.000 ms

$ sudo vppctl -s /run/vpp/cli-vpp1.sock
    _______    _        _   _____  ___
 __/ __/ _ \  (_)__    | | / / _ \/ _ \
 _/ _// // / / / _ \   | |/ / ___/ ___/
 /_/ /____(_)_/\___/   |___/_/  /_/
vpp# sh trace
sh trace

Packet 1
00:36:53:922325: af-packet-input
  af_packet: hw_if_index 1 next-index 4
    tpacket2_hdr:
      status 0x20000001 len 42 snaplen 42 mac 66 net 80
      sec 0x602bb753 nsec 0x13e8b14 vlan 0 vlan_tpid 0
00:36:53:922352: ethernet-input
  ARP: 16:1d:6c:36:33:7e -> ff:ff:ff:ff:ff:ff
00:36:53:922363: arp-input
  request, type ethernet/IP4, address size 6/4
  16:1d:6c:36:33:7e/10.10.1.1 -> 00:00:00:00:00:00/10.10.1.2
00:36:53:922373: arp-reply
  request, type ethernet/IP4, address size 6/4
  16:1d:6c:36:33:7e/10.10.1.1 -> 00:00:00:00:00:00/10.10.1.2
00:36:53:922718: host-vpp1out-output
  host-vpp1out
  ARP: 02:fe:06:c9:89:07 -> 16:1d:6c:36:33:7e
  reply, type ethernet/IP4, address size 6/4
  02:fe:06:c9:89:07/10.10.1.2 -> 16:1d:6c:36:33:7e/10.10.1.1
Packet 2
00:36:53:922943: af-packet-input
  af_packet: hw_if_index 1 next-index 4
    tpacket2_hdr:
      status 0x20000001 len 98 snaplen 98 mac 66 net 80
      sec 0x602bb753 nsec 0x149af45 vlan 0 vlan_tpid 0
00:36:53:922948: ethernet-input
00:36:53:922943: af-packet-input
  IP4: 16:1d:6c:36:33:7e -> 02:fe:06:c9:89:07
00:36:53:922952: ip4-input
  ICMP: 10.10.1.1 -> 10.10.1.2
    tos 0x00, ttl 64, length 84, checksum 0xfdcd dscp CS0 ecn NON_ECN
    fragment id 0x26c5, flags DONT_FRAGMENT
  ICMP echo_request checksum 0x912f id 1940
00:36:53:922969: ip4-lookup
  fib 0 dpo-idx 7 flow hash: 0x00000000
  ICMP: 10.10.1.1 -> 10.10.1.2
    tos 0x00, ttl 64, length 84, checksum 0xfdcd dscp CS0 ecn NON_ECN
    fragment id 0x26c5, flags DONT_FRAGMENT
  ICMP echo_request checksum 0x912f id 1940
...
```
