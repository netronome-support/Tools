#!/bin/bash

############################################################
: ${DPDK_APP_NAME:='ping-test'}
: ${DPDK_VERSION:=19.02}
: ${DPDK_IFACE_INDEX:=1}
: ${DPDK_PORT_INDEX:=0}
: ${APP_SRC_DIR:=$HOME/ping-test}
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

mkdir -p $APP_RESULTS_DIR
    check_status "faild to create $APP_RESULTS_DIR"

. /etc/dpdk-$DPDK_VERSION.conf

export RTE_OUTPUT=$DPDK_APP_BUILD_DIR

make -C $APP_SRC_DIR
    check_status ""

setup-hugepages.sh 256
    check_status ""

set-iface-mode.sh $DPDK_IFACE_INDEX dpdk
    check_status "failed to set interface to DPDK"

############################################################

cmd=( "$RTE_OUTPUT/ping-test" )
cmd+=( "-l" "1" )
cmd+=( "--socket-mem" "32" )
cmd+=( "-n" "3" )
cmd+=( "--" )
cmd+=( "--port" "$DPDK_PORT_INDEX" )
cmd+=( "--duration" "10" )
# cmd+=( "--count" "100000" )
cmd+=( "--l-ip-addr" "10.0.0.11" )
cmd+=( "--r-ip-addr" "10.0.0.10" )
# cmd+=( "--pkt-size" "64" )
cmd+=( "--rate" "100000" )
cmd+=( "--dump-file" "$APP_RESULTS_DIR/latency-dump.txt" )
cmd+=( "--log-file" "$APP_RESULTS_DIR/ping-test.log" )

############################################################
logfile="$APP_RESULTS_DIR/start-dpdk-ping-test.log"
cat <<EOF | tee -a $APP_RESULTS_DIR/results.log >> $logfile

# $(date)
EOF
############################################################
set -o pipefail

echo "CMD: ${cmd[@]} $*" \
    | tee -a $APP_RESULT_DIR/results.log \
    | tee -a $logfile
############################################################
${cmd[@]} $* \
    | tee -a $logfile
    check_status "ping test failed"
############################################################
./analyze-results.py "$APP_RESULTS_DIR/latency-dump.txt" \
    | tee -a $APP_RESULTS_DIR/results.log
############################################################

exit 0
