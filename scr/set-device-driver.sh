#!/bin/bash

toolname=$(basename $0)
########################################################################
function usage () {
cat <<EOF

$toolname - Tool for binding drivers to PCI devices.

This tool has some overlap in functionality with dpdk-devbind, but
$toolname is much faster.
Has special functions for identifying Netronome Agilio VF devices.

Syntax: $toolname [<options>] [<PCI BDF> ...]

Options:
  --help -h                     Print this help
  --verbose                     Print debug information
  --dry-run                     Just specify what would have been done
  --verify                      Just verify (and report if mismatch)
  --driver -d <name>            Specify driver
  --nfp-idx <idx>               Specify NFP device (0..)
  --nfp-vf-idx -i <idx>         Specify NFP VF by index
  --nfp-vf-idx -i <start>-<end> Specify a range of NFP VFs
  --pci-if-idx <idx>            Specify interface index from lspci list

Examples:
  $toolname -d vfio-pci 0a:08.3
    - Attach driver to PCI device
  $toolname -d none 0a:08.3 0a:08.4
    - Remove driver from PCI devices
  $toolname -d nfp_netvf --nfp-vf-idx 0-7
    - Attach driver to NFP VFs 0..7
  $toolname -d igb_uio --pci-if-idx 1
    - Attach driver to second Ethernet PCI device in lspci listing
  $toolname -d igb_uio --nfp-vf-idx 0-7 --verify
    - Return error code (-1) if the driver is not attached

EOF
}
########################################################################
function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($toolname): $errmsg"
        exit -1
    fi
}
########################################################################
function verbose() {
    local msg="$1"
    if [ "$optVerbose" != "" ]; then
        echo "$msg"
    fi
}
########################################################################
xd='[0-9a-fA-F]'
re_integer='^[0-9]+$'
re_index_range='^[0-9]+-[0-9]+$'
re_pci_0="^${xd}{4}:${xd}{2}:${xd}{2}\.[0-7]\$"
re_pci_1="^${xd}{2}:${xd}{2}\.[0-7]\$"
########################################################################
: ${NFP_DEV_INDEX:=0}
########################################################################
param=""
devlist=()
vf_idx_list=()
pci_if_list=()

for arg in "$@" ; do
    if [ "$param" == "" ]; then
        case "$arg" in
          "--help"|"-h") usage ; exit 0 ;;
          "--verbose")          optVerbose="yes" ;;
          "--dry-run")          optDryRun="yes" ;;
          "--driver"|"-d")      param="driver" ;;
          "--nfp-idx")          param="nfp-index" ;;
          "--nfp-vf-idx"|"-i")  param="vf-index" ;;
          "--pci-if-idx")       param="if-index" ;;
          "--verify")           optVerify="yes" ;;
          *)
            if   [[ "$arg" =~ $re_pci_0 ]]; then
                devlist+=( "$arg" )
            elif [[ "$arg" =~ $re_pci_1 ]]; then
                devlist+=( "0000:$arg" )
            else
                false ; check_status "could not parse '$arg'"
            fi
            ;;
        esac
    else
        case "$param" in
          "driver")             driver="$arg" ;;
          "nfp-index")          NFP_DEV_INDEX="$arg" ;;
          "vf-index")           vf_idx_list+=( "$arg" ) ;;
          "if-index")           pci_if_list+=( "$arg" ) ;;
        esac
    param=""
    fi
done

########################################################################
verbose "Running: $0 $*"
########################################################################
pkgs=()
pkgs+=( "lspci@pciutils" )
install-packages.sh ${pkgs[@]} \
    || exit -1
########################################################################
statcmd="stat --format '%d-%i' --dereference"
function get_driver_id () {
    local driver="$1"
    if [ "$driver" == "none" ]; then
        printf "none"
    else
        $statcmd /sys/bus/pci/drivers/$driver
    fi
}
function get_device_driver_id () {
    local pcibdf="$1"
    local devdir="/sys/bus/pci/devices/$pcibdf"
    if [ ! -d $devdir/driver ]; then
        printf "none"
    else
        $statcmd $devdir/driver
    fi
}
########################################################################
test "$driver" != ""
    check_status "no driver specified"

if [ "$driver" != "none" ]; then
    drvdir="/sys/bus/pci/drivers/$driver"
    if [ ! -d "$drvdir" ]; then
        verbose "running 'modprobe' on $driver"
        modprobe $driver > /dev/null 2>&1
            check_status "could not 'modprobe' driver '$driver'"
    fi
    test -d "$drvdir"
        check_status "no such driver '$driver'"
    bindfile="$drvdir/bind"
    test -w $bindfile
        check_status "access denied to $bindfile"
    # Used to identify the driver of a PCI device
fi
driver_id=$(get_driver_id $driver)
########################################################################
function add_nfp_vf_idx () {
    local idx="$1"
    local pci_dev=$(( 8 + idx / 8 ))
    local pci_fnc=$(( idx % 8 ))
    printf -v pci_bdf "0000:%s:%02x.%u" "$nfpbus" $pci_dev $pci_fnc
    verbose "Translating VF index $idx to $pci_bdf"
    devlist+=( "$pci_bdf" )
}
########################################################################
if [ ${#vf_idx_list[@]} -gt 0 ]; then
    nfp_pf_bus_list=( $(lspci -d 19ee: \
        | cut -d ' ' -f 1 \
        | sed -rn 's/(:00\.0)$/\1/p' \
        | cut -d ':' -f 1 ) )
    test "${#nfp_pf_bus_list[@]}" -gt 0
        check_status "could not identify an NFP in the system"
    [[ "$NFP_DEV_INDEX" =~ $re_integer ]]
        check_status "NFP index must be an integer ($NFP_DEV_INDEX)"
    verbose "NFP device (bus) list: ${nfp_pf_bus_list[*]}"
    nfpbus=${nfp_pf_bus_list[$NFP_DEV_INDEX]}
    test "$nfpbus" != ""
        check_status "no NFP[$NFP_DEV_INDEX] present in the system"
    verbose "Selected NFP device at 0000:$nfpbus:00.0"
    for nfpidx in ${vf_idx_list[@]} ; do
        if [[ "$nfpidx" =~ $re_integer ]]; then
            test $nfpidx -lt 60
                check_status "NFP VF index '$nfpidx' is out or range"
            add_nfp_vf_idx "$nfpidx"
        elif [[ "$nfpidx" =~ $re_index_range ]]; then
            start=${nfpidx%-*}
            end=${nfpidx#*-}
            test \( $start -le $end \) -a \( $end -lt 60 \)
                check_status "illegal NFP VF index range ($nfpidx)"
            for idx in $(seq $start $end) ; do
                add_nfp_vf_idx $idx
            done
        else
            false ; check_status "illegal index format ($nfpidx)"
        fi
    done
fi
########################################################################
if [ ${#pci_if_list[@]} -gt 0 ]; then
    pci_eth_dev_list=( $(lspci \
        | grep 'Ethernet controller' \
        | cut -d ' ' -f 1) )
    for idx in ${pci_if_list[@]} ; do
        test "${pci_eth_dev_list[$idx]}" != ""
            check_status "no PCI Ethernet interface with index $idx"
        devlist+=( "0000:${pci_eth_dev_list[$idx]}" )
    done
fi
########################################################################
faillist=()
verbose "Device List: ${devlist[@]}"
for pcibdf in ${devlist[@]} ; do
    devdir="/sys/bus/pci/devices/$pcibdf"
    test -d $devdir
        check_status "device '$pcibdf' does not exist"
    dev_drv_id=$(get_device_driver_id $pcibdf)
    if [ "$dev_drv_id" == "$driver_id" ]; then
        verbose "[$pcibdf] no change needed ($dev_drv_id)"
        continue
    elif [ "$optVerify" != "" ]; then
        faillist+=( "$pcibdf" )
        continue
    fi
    if [ -d $devdir/driver ]; then
        verbose "[$pcibdf] unbinding"
        if [ "$optDryRun" != "" ]; then
            echo "Would write '$pcibdf' to $devdir/driver/unbind"
        else
            echo "$pcibdf" > $devdir/driver/unbind
                check_status "failed to unbind $bdf"
        fi
    fi
    if [ "$driver" != "none" ]; then
        verbose "[$pcibdf] binding to $driver"
        orfile="$devdir/driver_override"
        test -w $orfile
            check_status "access denied to $orfile"
        test -w $bindfile
            check_status "can not bind $pcibdf to $driver"
        if [ "$optDryRun" != "" ]; then
            echo "Would write '$driver' to $orfile"
            echo "Would write '$pcibdf' to $bindfile"
        else
            echo "$driver" > $orfile
            echo "$pcibdf" > $bindfile
        fi
    fi
done
########################################################################
if [ "$optVerify" != "" ] && [ ${#faillist[@]} -gt 0 ]; then
    echo "FAIL: ${faillist[@]}"
    exit -1
fi
########################################################################
verbose "SUCCESS"
exit 0
