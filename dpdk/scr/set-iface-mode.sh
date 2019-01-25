#!/bin/bash

function f_usage () {
cat <<EOF
Usage: $0 <interface index> dpdk|netdev|none
EOF
}

re_index='^[0-9]+$'
if ! [[ "$1" =~ $re_index ]]; then
    f_usage
    exit -1
fi

case "$2" in
  "dpdk"|"netdev"|"none")
    ;;
  *)
    f_usage
    exit -1
esac

ifidx=$1
mode=$2

########################################################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        if [ "$errmsg" != "" ]; then
            echo "ERROR($(basename $0)): $errmsg" >&2
        fi
        exit -1
    fi
}

########################################################################
##  Check for all required tools

which dpdk-devbind > /dev/null 2>&1
    check_status "missing tool 'dpdk-devbind'"

pkgs=()
pkgs+=( "lspci@pciutils" )
pkgs+=( "ifconfig@net-tools" )

install-packages.sh ${pkgs[@]} \
    || exit -1

########################################################################
##  Get list of 'Ethernet controller' PCI devices

bdflist=( $( lspci \
    | sed -rn 's/^(\S+)\s+Ethernet controller.*$/\1/p' \
    ) )

bdf=${bdflist[$ifidx]}

test "$bdf" != ""
    check_status "no such device (ifidx=$ifidx) on $(hostname)"

########################################################################
##  Based on PCI Bus-Device-Function - value, search for a corresponding
##  interface.

function get_devname () {
    local bdf="$1"
    devname=""

    devdir=$(find /sys/bus/pci/devices -type l -name "*$bdf")

    if [ "$devdir" == "" ]; then
        return
    fi

    if [ -d "$devdir/net" ]; then
        local netdir="$devdir/net"
    else
        local viodir=$(find -L $devdir -maxdepth 1 -type d -name 'virtio*')
        if [ ! -d "$viodir/net" ]; then
            return
        fi
        local netdir="$viodir/net"
    fi

    devname=$(find $netdir -maxdepth 1 -type d -printf '%P' \
        | head -1)
}

########################################################################

type=$( lspci -s $bdf -n | cut -d ' ' -f 3 )
p_driver=""
b_driver=""

case "$type" in
    "19ee:6003") vftype="NFP"
        b_driver="nfp_netvf" ; p_driver="nfp" ;;
    "1af4:1000") vftype="VirtIO"
        b_driver="virtio-pci" ; p_driver="virtio-pci" ;;
    *)
        echo "ERROR: unidentified interface type $type on $(hostname)"
        exit -1
esac

if [ "$mode" != "netdev" ]; then
    get_devname "$bdf"
    if [ "$devname" != "" ]; then
        ifconfig $devname 0 down
            check_status "failed to set $devname to DOWN"
    fi
fi

case "$mode" in
  "dpdk")
    b_driver="igb_uio"
    grep hugetlbfs /proc/mounts > /dev/null \
        || mount /mnt/huge
    ;;
  "netdev")
    ;;
  "none")
    driver="none"
    ;;
  *)
    echo "ERROR: unknown mode '$mode'"
    exit -1
esac

# Always load 'igb_uio' for dpdk-devbind
modprobe igb_uio \
    || exit -1

if [ "$p_driver" != "" ]; then
    modprobe $p_driver
        check_status "'modprobe $p_driver' failed"
fi

c_driver=$(dpdk-devbind --status \
    | sed -rn "s/^\S*$bdf"' .* drv=(\S+).*$/\1/p')

if [ "$c_driver" != "$b_driver" ]; then
    dpdk-devbind --bind $b_driver $bdf
        check_status "failed to bind $b_driver to $bdf"
fi

exit 0
