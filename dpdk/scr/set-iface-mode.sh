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
    rc=$? ; errmsg="$1"
    if [ $rc -ne 0 ]; then
        if [ "$errmsg" != "" ]; then
            echo "ERROR($(basename $0)): $errmsg" >&2
        fi
        exit -1
    fi
}

########################################################################
##  Check for all required tools

pkgs=()
pkgs+=( "lspci@pciutils" )
pkgs+=( "ifconfig@net-tools" )

install-packages.sh ${pkgs[@]} \
    || exit -1

########################################################################
##  Get list of 'Ethernet controller' PCI devices

hostname="$(hostname)"

bdflist=( $( lspci \
    | sed -rn 's/^(\S+)\s+Ethernet controller.*$/\1/p' \
    ) )

bdf="${bdflist[$ifidx]}"

test "$bdf" != ""
    check_status "no such device (ifidx=$ifidx) on $hostname"

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

pci_type=$( lspci -s $bdf -n | cut -d ' ' -f 3 )
pci_vendor=${pci_type/:*}
pci_device=${pci_type/*:}

probe_drivers=""
netdev_driver=""
dpdk_driver="igb_uio"

if [ "$pci_vendor" == "19ee" ]; then
    # Netronome NFP
    netdev_driver="nfp_netvf"
    probe_driver="nfp"
elif  [ "$pci_vendor" == "15b3" ]; then
    # Mellanox
    netdev_driver="mlx5_core"
    dpdk_driver="mlx5_core"
elif [ "$pci_type" == "1af4:1000" ]; then
    # Red Hat VirtIO networ device
    netdev_driver="virtio-pci"
else
    false ; check_status "unidentified interface type $type on $(hostname)"
fi

if [ "$mode" != "netdev" ]; then
    get_devname "$bdf"
    if [ "$devname" != "" ]; then
        ifconfig $devname 0 down
            check_status "failed to set $devname to DOWN"
    fi
fi

case "$mode" in
  "dpdk")   driver="$dpdk_driver" ;;
  "netdev") driver="$netdev_driver" ;;
  "none")   driver="none" ;;
  *)
    echo "ERROR: unknown mode '$mode'"
    exit -1
esac

for drv in $probe_drivers $driver ; do
    modprobe $drv
        check_status "'modprobe $drv' failed"
done

exec set-device-driver.sh --driver $driver $bdf
