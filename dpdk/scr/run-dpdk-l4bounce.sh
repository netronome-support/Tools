#!/bin/bash

prtidx="$1"

projname="l4bounce"

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
l4bounce(struct rte_mbuf *m, unsigned portid)
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
        switch (iphp->next_proto_id) {
            case IPPROTO_UDP:
            case IPPROTO_TCP:
            case IPPROTO_SCTP: {
                /* L4 Protocol Pointer */
                int l3hdrlen = 4 * (0x0f & iphp->version_ihl);
                uint16_t *l4pp = (uint16_t *) &((char *) iphp)[l3hdrlen];
                /* Swap the Port fields */
                uint16_t tmp = l4pp[1];
                l4pp[1] = l4pp[0];
                l4pp[0] = tmp;
                }
                break;
        }
    }

    buffer = tx_buffer[portid];
    sent = rte_eth_tx_buffer(portid, 0, buffer, m);
    if (sent)
        port_statistics[portid].tx += sent;
}

EOF

sed -r 's/\sl2fwd_simple_forward/l4bounce/' \
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

sed -r 's/l2fwd_/l4b_/g' \
    -i $srcdir/main.c \
    || exit -1

incl="#include \"bounce.c\""
sed -r "/^static uint64_t timer_period/a $incl" \
    -i $srcdir/main.c \
    || exit -1

sed -r 's/^(APP).*$/\1 = l4bounce/' \
    -i $srcdir/Makefile \
    || exit -1

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
