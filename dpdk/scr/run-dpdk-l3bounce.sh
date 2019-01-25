#!/bin/bash

prtidx="$1"

projname="l3bounce"

# This script makes a copy of l2fwd and modifies it so that packets are returned
# to the port that they came in on and with reversed IP and Ethernet addresses.
#
# The script assumes DPDK variables to be specified in /etc/dpdk.conf
#
# The script will launch the DPDK application on specified DPDK port. Note that
# the application crashes if one attempts to run it on multiple DPDK ports.

if [ "$prtidx" == "" ] || [ "${prtidx##*[!0-9]*}" == "" ]; then
    echo "ERROR: specify port index"
    exit -1
fi

if [ ! -f /etc/dpdk.conf ]; then
    echo "ERROR: missing /etc/dpdk.conf"
    exit -1
fi

. /etc/dpdk.conf

if [ ! -d $RTE_SDK/examples/l2fwd ]; then
    echo "ERROR: missing $RTE_SDK/examples/l2fwd"
    exit -1
fi

srcdir="/opt/src/$projname"
mkdir -p $srcdir
/bin/cp -f \
    $RTE_SDK/examples/l2fwd/* \
    $srcdir \
    || exit -1

cat <<EOF > $srcdir/bounce.c

#include <stdint.h>
#include <rte_ether.h>
#include <rte_ip.h>

static inline void
l3bounce(struct rte_mbuf *m, unsigned portid)
{
    struct ether_hdr *eth;
    int sent;
    struct rte_eth_dev_tx_buffer *buffer;

    eth = rte_pktmbuf_mtod(m, struct ether_hdr *);

    struct ether_addr mac;
    ether_addr_copy(&eth->s_addr, &mac);
    ether_addr_copy(&eth->d_addr, &eth->s_addr);
    ether_addr_copy(&mac,         &eth->d_addr);

    if (ntohs(eth->ether_type) == ETHER_TYPE_IPv4) {
        struct ipv4_hdr *iphp = (void *) &eth[1];
        uint32_t tmp = iphp->src_addr;
        iphp->src_addr = iphp->dst_addr;
        iphp->dst_addr = tmp;
    }

    buffer = tx_buffer[portid];
    sent = rte_eth_tx_buffer(portid, 0, buffer, m);
    if (sent)
        port_statistics[portid].tx += sent;
}

EOF

sed -r 's/\sl2fwd_simple_forward/l3bounce/' \
    -i $srcdir/main.c \
    || exit -1

sed -r 's/(X_DESC_DEFAULT)\s+[0-9]+$/\1 1024/' \
    -i $srcdir/main.c \
    || exit -1

sed -r 's/(define NB_MBUF)\s+[0-9]+$/\1 32768/' \
    -i $srcdir/main.c \
    || exit -1

sed -r 's/^(l2fwd_simple_forward)/__attribute__((unused)) \1/' \
    -i $srcdir/main.c \
    || exit -1

sed -r 's/l2fwd_/l3b_/g' \
    -i $srcdir/main.c \
    || exit -1

incl="#include \"bounce.c\""
sed -r "/^static uint64_t timer_period/a $incl" \
    -i $srcdir/main.c \
    || exit -1

sed -r 's/^(APP).*$/\1 = l3bounce/' \
    -i $srcdir/Makefile \
    || exit -1

export RTE_OUTPUT="$HOME/.cache/dpdk/$projname"
mkdir -p $RTE_OUTPUT

make -C $srcdir install \
    || exit -1

printf -v coremask "0x%04x" $(( 1 << ( prtidx + 1 ) ))
printf -v portmask "0x%04x" $(( 1 << ( prtidx ) ))

cmd=( "$RTE_OUTPUT/$projname" )
cmd+=( "-c" "$coremask" )
cmd+=( "-n" "2" )
cmd+=( "-m" "128" )
cmd+=( "--file-prefix" "$projname_p$prtidx" )
cmd+=( "--" )
cmd+=( "-T" "1" )
cmd+=( "-p" "$portmask" )

cat << EOF | tee -a /var/log/dpdk-$projname.cmd
--------------------------------
Date: $(date)
Command:  ${cmd[@]}
EOF

exec ${cmd[@]}
