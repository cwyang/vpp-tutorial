# vpp-conf.sh
#
# usage: vpp-conf.sh [vpp-id]
#        vpp -c <(./vpp-conf.sh vpp1)
ID=$1
if [ -z ${ID:+x} ]; then
    ID=vpp
fi    
cat<<EOF
heapsize 4G
cpu {
    main-core 1
    skip-cores 1
    workers 3
}
unix {
    #interactive
    cli-listen /run/vpp/${ID}.sock
    log /var/log/vpp/${ID}.log
}
api-segment {
    prefix ${ID}
}
logging {
    default-log-level debug
    default-syslog-log-level debug
}
plugins {
    plugin dpdk_plugin.so { disable }
}
statseg {
    default
}
EOF
