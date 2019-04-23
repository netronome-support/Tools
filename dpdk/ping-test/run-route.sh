#!/bin/bash

############################################################
: ${DPDK_APP_NAME:='route'}
: ${DPDK_VERSION:=19.02}
: ${DPDK_IFACE_INDEX:=1}
: ${DPDK_PORT_INDEX:=0}
: ${APP_SRC_DIR:=/opt/git/netronome-support/Tools/dpdk/route}
: ${DPDK_BUILD_DIR:=$HOME/.local/build/dpdk}
: ${DPDK_APP_BUILD_DIR=$DPDK_BUILD_DIR/$DPDK_APP_NAME}
: ${APP_RESULTS_DIR:=$HOME/.local/dpdk-$DPDK_APP_NAME}
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
install-netronome-support-tools.sh
    check_status ""
install-dpdk.sh $DPDK_VERSION
    check_status ""
############################################################

. /etc/dpdk-$DPDK_VERSION.conf

export RTE_OUTPUT=$DPDK_APP_BUILD_DIR

make -C $APP_SRC_DIR
    check_status ""

setup-hugepages.sh 256
    check_status ""

set-iface-mode.sh $DPDK_IFACE_INDEX dpdk
    check_status "failed to set interface to DPDK"

############################################################

cmd=( "$RTE_OUTPUT/route" )

eal=()
# Cores (WARNING - more than one may cause issues)
eal+=("-c" "6" )
eal+=("-n" "2" )

arg=()
# Port Bitmask (in hexadecimal)
arg+=( "-p" "1" )
# Number of Queues per core
arg+=( "-q" "4" )

# arg+=( "--no-statistics" )

arg+=( "--log-file" "/var/log/dpdk-route.log" )
arg+=( "--log-level" 3 )
arg+=( "--log-pkt-len" 18 )
arg+=( "--log-packets" )

arg+=( "--iface-addr" "0:1#10.0.0.10/24" )

exec ${cmd[@]} ${eal[@]} -- ${arg[@]}
