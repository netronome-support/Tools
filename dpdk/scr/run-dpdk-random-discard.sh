#!/bin/bash

projname="random-discard"

########################################################################
#
# This script makes a copy of l2fwd and modifies it so that packets are
# passed between two DPDK ports with a specified randon discard rate.
#
# The script assumes DPDK variables to be specified in /etc/dpdk.conf
#
# The application assumes that at least two DPDK port are available and
# specified (by index) on the command line.
#
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
Syntax: $(basename $0) [<options>] <port-0 index> <port-1 index> <discard rate [%]>
Example $(basename $0) 0 1 5.0
Options:
  --build-only
  --build-dir <path>        - Location for source code
  --rte-sdk <path>          - Location of DPDK (RTE_SDK)
  --dpdk-config <fname>     - Specify file with DPDK variables
  --max-pkt-size <size>     - Specify maximum Ethernet packet size
  --rte-output <path>       - Build directory (RTE_OUTPUT)
EOF
}

########################################################################

param=""
cnt=0
for arg in "$@" ; do
    if [ "$param" == "" ]; then
        case "$arg" in
            "--help"|"-h")
                usage
                exit 0
                ;;
            "--build-only")     optBuildOnly="yes" ;;
            "--build-dir")      param="build-dir" ;;
            "--rte-sdk")        param="rte-sdk" ;;
            "--dpdk-config")    param="dpdk-config" ;;
            "--max-pkt-size")   param="max-pkt-size" ;;
            "--rte-output")     param="rte-output" ;;
        *)
            case $cnt in
              0) prt0idx="$arg" ;;
              1) prt1idx="$arg" ;;
              2) discrate="$arg" ;;
            esac
            test $cnt -lt 3
                check_status "too many arguments"
            cnt=$(( cnt + 1 ))
            ;;
        esac
    else
        case "$param" in
            "build-dir")        DPDK_BUILD_DIR="$arg" ;;
            "rte-sdk")          RTE_SDK="$arg" ;;
            "dpdk-config")      DPDK_CONF_FILE="$arg" ;;
            "max-pkt-size")     DPDK_SET_MAX_ETH_PKT_SIZE="$arg" ;;
            "rte-output")       RTE_OUTPUT="$arg" ;;
        esac
        param=""
    fi
done

test "$param" == ""
    check_status "argument missing for '--$param'"

########################################################################
##  Defaults

: ${DPDK_CONF_FILE:=/etc/dpdk.conf}
: ${DPDK_BUILD_DIR:=$HOME/.local/build/dpdk/$projname}
: ${DPDK_APP_PRINT_INTERVAL:=1}
: ${RTE_OUTPUT:=$DPDK_BUILD_DIR/build}

########################################################################

if [ "$optBuildOnly" != "yes" ]; then
    test $cnt -eq 3
        check_status "too few arguments"
    test "${prt0idx##*[!0-9]*}" != ""
        check_status "first argument should be <port-0 index>"
    test "${prt1idx##*[!0-9]*}" != ""
        check_status "second argument should be <port-1 index>"
    test "${discrate##*[!0-9.]*}" != ""
        check_status "third argument should be <discard rate>"
    test $prt0idx -ne $prt1idx
        check_status "two different ports must be specified"
fi

########################################################################

which install-packages.sh > /dev/null 2>&1
    check_status 'install-packages.sh is not installed'
pkgs=()
pkgs+=( 'bc@' 'sed@' )
pkgs+=( 'make@' 'gcc@' )
install-packages.sh ${pkgs[@]}
    check_status ""

########################################################################

if [ "$DPDK_CONF_FILE" != "NONE" ]; then
    test -f $DPDK_CONF_FILE
        check_status "missing DPDK configuration '$DPDK_CONF_FILE"
    . $DPDK_CONF_FILE
fi

test -d $RTE_SDK/examples/l2fwd
    check_status "missing $RTE_SDK/examples/l2fwd"

########################################################################
##  Try to figure out a vCPU bitmap

: ${DPDK_APP_SKIP_VCPU_COUNT:=1}
: ${DPDK_APP_USE_VCPU_COUNT:=3}

if [ "$DPDK_APP_CORE_MASK" == "" ]; then
    # Create a list of 3 vCPUs (skipping the first) that are on
    # different cores on the specified (or first) socket:
    opts=()
    opts+=( "--skip" "$DPDK_APP_SKIP_VCPU_COUNT" )
    opts+=( "--count" "$DPDK_APP_USE_VCPU_COUNT" )
    if [ "$DPDK_APP_SOCKET" != "" ]; then
        opts+=( "--socket" "$DPDK_APP_SOCKET" )
    fi
    list=( $(list-socket-vcpus.sh ${opts[@]}) )
    # Convert the list to a bitmap:
    bitmap=0
    for vcpuidx in ${list[@]} ; do
        bitmap=$(( bitmap + ( 1 << vcpuidx ) ))
    done
    if [ ${#list[@]} -le 1 ]; then
        bitmap=$(( bitmap | 1 ))
    fi
    printf -v DPDK_APP_CORE_MASK "0x%x" "$bitmap"
fi

########################################################################

srcdir="$DPDK_BUILD_DIR"
mkdir -p $srcdir
    check_status "failed to 'mkdir $srcdir'"
cp -rf $RTE_SDK/examples/l2fwd/* $srcdir
    check_status "failed to copy l2fwd files"

########################################################################

cat <<EOF > $srcdir/random-discard.c

#include <stdint.h>
#include <stdlib.h>
#include <rte_random.h>

struct {
    int initialized;
    uint64_t level;
} glob = { 0, 0 };

static inline void
read_discard_level_variable (void)
{
    glob.initialized = 1;
    const char *str = getenv("rand_discard_level");
    if (str != NULL)
        glob.level = atoll(str);
}

static inline void
random_discard(struct rte_mbuf *m, unsigned portid)
{
    int sent;
    struct rte_eth_dev_tx_buffer *buffer;

    unsigned dst_port = rnd_disc_dst_ports[portid];

    if (!glob.initialized) {
        read_discard_level_variable();
    }

    uint64_t rnd = (uint64_t) (uint32_t) rte_rand();
    if (rnd < glob.level) {
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

sed -r "s/^(APP).*\$/\1 = $projname/" \
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
##  Bug suppression:

sed -r 's/uint32_t (\S+_enabled_port_mask)/uint64_t \1/' \
    -i $srcdir/main.c
    check_status "failed to patch source code"

sed -r 's/\(1 << portid\)/((uint64_t) 1 << portid)/' \
    -i $srcdir/main.c
    check_status "failed to patch source code"

########################################################################

mkdir -p $RTE_OUTPUT
    check_status "failed to create '$RTE_OUTPUT' directory"
export RTE_OUTPUT

make -C $srcdir
    check_status "failed to make DPDK Randon Discard Application"

test -x $RTE_OUTPUT/$projname
    check_status "build did not create '$RTE_OUTPUT/$projname'"

########################################################################

if [ "$optBuildOnly" == "yes" ]; then
    cp -f $RTE_OUTPUT/$projname /usr/local/bin/dpdk-$projname
        check_status "failed to copy generated binary to /usr/local/bin"
    exit 0
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
##  Pass the 'random discard rate' via an env. variable

export rand_discard_level

########################################################################

cmd=( "$RTE_OUTPUT/$projname" )
cmd+=( "-c" "$DPDK_APP_CORE_MASK" )
cmd+=( "-n" "2" )
cmd+=( "-m" "128" )
cmd+=( "--" )
cmd+=( "-T" "$DPDK_APP_PRINT_INTERVAL" )
cmd+=( "-p" "$portmask" )

########################################################################

cat << EOF | tee -a /var/log/dpdk-$projname.cmd
--------------------------------
Date: $(date)
Command: ${cmd[@]}
EOF

########################################################################

exec ${cmd[@]}

########################################################################
