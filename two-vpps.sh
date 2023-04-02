# two_vpps

VPPCTL=/usr/local/bin/vppctl
VPP=/usr/local/bin/vpp
VPPCONF=./vpp-conf.sh
NS=router

sudo killall $VPP
#sudo bash -c "ip netns exec $NS $VPP -c1 <($VPPCONF vpp1)"
sudo bash -c "ip netns exec $NS $VPP -c1 vpp1.conf"
sudo bash -c "(cd /home/vagrant/vpp-dev; ip netns exec $NS make debug)"

