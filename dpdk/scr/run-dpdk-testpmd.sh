#!/bin/bash

############################################################
function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        if [ "$errmsg" != "" ]; then
            echo "ERROR($(basename $0)): $errmsg" >&2
        fi
        exit -1
    fi
}

############################################################

if [ "$RTE_SDK" == "" ]; then
    test -f /etc/dpdk.conf
        check_status "/etc/dpdk.conf is missing"

    . /etc/dpdk.conf
fi

test -d $RTE_SDK
    check_status "DPDK missing (at $RTE_SDK)"

testpmd="$RTE_SDK/build/app/testpmd"

test -x $testpmd
    check_status "DPDK is missing 'testpmd' (at $testpmd)"

############################################################

which setup-hugepages.sh > /dev/null
    check_status "missing tool setup-hugepages.sh"

setup-hugepages.sh --min-pages 128
    check_status "failed to setup Hugepages"

############################################################

which set-iface-mode.sh > /dev/null
    check_status "missing tool set-iface-mode.sh"

set-iface-mode.sh 1 dpdk
    check_status "failed to set interface to DPDK"
set-iface-mode.sh 2 dpdk
    check_status "failed to set interface to DPDK"

############################################################

cmd=( "$testpmd" )
cmd+=( "-l" "1-3" )
cmd+=( "--socket-mem" "32" )
cmd+=( "-n" "3" )
cmd+=( "--" )
cmd+=( "--portmask=0x03" )
cmd+=( "--total-num-mbufs" "8192" )
cmd+=( "--nb-cores=2" )
cmd+=( "--disable-hw-vlan" )
cmd+=( "--forward-mode=io" )
cmd+=( "--auto-start" )

############################################################
logdir="/var/log"
logfile="$logdir/start-testpmd.log"
cat <<EOF >> $logfile
# $(date)
${cmd[@]}

EOF
############################################################

exec ${cmd[@]}
