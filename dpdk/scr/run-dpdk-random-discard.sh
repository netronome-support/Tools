#!/bin/bash

prt0idx="$1"
prt1idx="$2"
discrate="$3"

projname="random-discard"

########################################################################
#
# This script makes a copy of l2fwd and modifies it so that packets are
# passed between two DPDK ports with a specified randon discard rate.
#
# The script assumes DPDK variables to be specified in /etc/dpdk.conf
#
########################################################################
: ${DPDK_CONF_FILE:=/etc/dpdk.conf}
: ${DPDK_BUILD_DIR:=$HOME/.local/build/dpdk}
: ${DPDK_APP_CORE_MASK:=7}
########################################################################
function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        if [ "$errmsg" != "" ]; then
            echo "ERROR($toolname): $errmsg"
        fi
        exit -1
    fi
}
########################################################################
function usage () {
cat <<EOF
Syntax: $(basename $0) <port-0 index> <port-1 index> <discard rate [%]>
Example $(basename $0) 0 1 5.0
EOF
}

########################################################################

if [ "$prt0idx" == "" ] || [ "${prt0idx##*[!0-9]*}" == "" ]; then
    echo "ERROR: first argument should be <port-0 index>"
    usage
    exit -1
fi
if [ "$prt1idx" == "" ] || [ "${prt1idx##*[!0-9]*}" == "" ]; then
    echo "ERROR: second argument should be <port-1 index>"
    usage
    exit -1
fi
if [ "$discrate" == "" ] || [ "${discrate##*[!0-9.]*}" == "" ]; then
    echo "ERROR: third argument should be <discard rate>"
    usage
    exit -1
fi

########################################################################
set -o pipefail
rand_discard_level=$(echo "scale=12 ; $discrate * 0.01 * 2^31" \
    | bc \
    | sed -r 's/\..*$//')
    check_status "failed to parse '$discrate'"
printf -v portmask "%x" \
    $(( ( 1 << $prt0idx ) | ( 1 << $prt1idx ) ))
########################################################################

if [ "$DPDK_CONF_FILE" != "NONE" ]; then
    test -f $DPDK_CONF_FILE
        check_status "missing DPDK configuration '$DPDK_CONF_FILE"
    . $DPDK_CONF_FILE
fi

test -d $RTE_SDK/examples/l2fwd
    check_status "missing $RTE_SDK/examples/l2fwd"

########################################################################
srcdir="$DPDK_BUILD_DIR/$projname"
mkdir -p $srcdir
    check_status "failed to 'mkdir $srcdir'"
cp -rf $RTE_SDK/examples/l2fwd/* $srcdir
    check_status "failed to copy l2fwd files"

########################################################################
cat <<EOF > $srcdir/random-discard.c

#include <stdint.h>
#include <rte_random.h>

static inline void
random_discard(struct rte_mbuf *m, unsigned portid)
{
    int sent;
    struct rte_eth_dev_tx_buffer *buffer;

    unsigned dst_port = rnd_disc_dst_ports[portid];

    uint64_t rnd = (uint64_t) (uint32_t) rte_rand();
    if (rnd < (double) $rand_discard_level) {
        rte_pktmbuf_free(m);
        return;
    }

    buffer = tx_buffer[dst_port];
    sent = rte_eth_tx_buffer(dst_port, 0, buffer, m);
    if (sent)
        port_statistics[dst_port].tx += sent;
}

EOF
########################################################################

sed -r 's/\sl2fwd_simple_forward/random_discard/' \
    -i $srcdir/main.c
    check_status "failed to patch source code"

sed -r 's/(X_DESC_DEFAULT)\s+[0-9]+$/\1 1024/' \
    -i $srcdir/main.c
    check_status "failed to patch source code"

sed -r 's/(define NB_MBUF)\s+[0-9]+$/\1 32768/' \
    -i $srcdir/main.c
    check_status "failed to patch source code"

sed -r 's/^(l2fwd_simple_forward)/__attribute__((unused)) \1/' \
    -i $srcdir/main.c
    check_status "failed to patch source code"

sed -r 's/l2fwd_/rnd_disc_/g' \
    -i $srcdir/main.c
    check_status "failed to patch source code"

incl="#include \"random-discard.c\""
sed -r "/^static uint64_t timer_period/a $incl" \
    -i $srcdir/main.c
    check_status "failed to patch source code"

sed -r 's/^(APP).*$/\1 = random-discard/' \
    -i $srcdir/Makefile
    check_status "failed to patch source code"

########################################################################

if [ "$DPDK_SET_MAX_ETH_PKT_SIZE" != "" ]; then
    # Re-configure the Interface MTU
    insert="rte_eth_dev_set_mtu(portid, $DPDK_SET_MAX_ETH_PKT_SIZE);"
    sed -r "s/(ret = rte_eth_dev_start)/$insert \1/" \
        -i $srcdir/main.c
        check_status "failed to patch source code"

    # Set the MTUs to hold enough data
    insert="(($DPDK_SET_MAX_ETH_PKT_SIZE) + RTE_PKTMBUF_HEADROOM)"
    sed -r "s/RTE_MBUF_DEFAULT_BUF_SIZE/$insert/g" \
        -i $srcdir/main.c
        check_status "failed to patch source code"

fi

########################################################################
# Bug suppression:

sed -r 's/uint32_t (\S+_enabled_port_mask)/uint64_t \1/' \
    -i $srcdir/main.c
    check_status "failed to patch source code"

sed -r 's/\(1 << portid\)/((uint64_t) 1 << portid)/' \
    -i $srcdir/main.c
    check_status "failed to patch source code"

########################################################################

export RTE_OUTPUT="$HOME/.cache/dpdk/$projname"
mkdir -p $RTE_OUTPUT

make -C $srcdir
    check_status "failed to make DPDK Randon Discard Application"

test -x $RTE_OUTPUT/$projname
    check_status "build did not create '$RTE_OUTPUT/$projname'"

########################################################################

cmd=( "$RTE_OUTPUT/$projname" )
cmd+=( "-c" "$DPDK_APP_CORE_MASK" )
cmd+=( "-n" "2" )
cmd+=( "-m" "128" )
cmd+=( "--" )
cmd+=( "-T" "1" )
cmd+=( "-p" "$portmask" )

########################################################################
cat << EOF | tee -a /var/log/dpdk-$projname.cmd
--------------------------------
Date: $(date)
Command:  ${cmd[@]}
EOF
########################################################################
exec ${cmd[@]}
########################################################################
