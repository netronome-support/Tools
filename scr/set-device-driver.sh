#!/bin/bash

########################################################################
function usage () {
cat <<EOF

Tool for binding drivers to PCI devices.
Has special functions for identifying Netronome Agilio VF devices.

Syntax: $(basename $0) [<options>] [<PCI BDF> ...]

Options:
  --help -h                     Print this help
  --verbose                     Print debug information
  --verify                      Just verify (and report if mismatch)
  --driver -d <name>            Specify driver
  --nfp-vf-idx -i <idx>         Specify NFP VF by index
  --nfp-vf-idx -i <start>-<end> Specify a range of NFP VFs
  --pci-if-idx <index>          Specify interface index from lspci list

EOF
}
########################################################################
function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
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
param=""
devlist=()
vf_idx_list=()
pci_if_list=()

for arg in "$@" ; do
    if [ "$param" == "" ]; then
        case "$arg" in
          "--help"|"-h") usage ;;
          "--verbose")          optVerbose="yes" ;;
          "--driver"|"-d")      param="driver" ;;
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
          "vf-index")           vf_idx_list+=( "$arg" ) ;;
          "if-index")           pci_if_list+=( "$arg" ) ;;
        esac
    param=""
    fi
done

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
    verbose "translating VF index $idx to $pci_bdf"
    devlist+=( "$pci_bdf" )
}
########################################################################
if [ ${#vf_idx_list[@]} -gt 0 ]; then
    nfpbus=$(lspci -d 19ee: \
        | head -1 \
        | cut -d ' ' -f 1 \
        | cut -d ':' -f 1 )
    test "$nfpbus" != ""
        check_status "could not identify an NFP in the system"
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
        echo "$pcibdf" > $devdir/driver/unbind
            check_status "failed to unbind $bdf"
    fi
    if [ "$driver" != "none" ]; then
        verbose "[$pcibdf] binding to $driver"
        orfile="$devdir/driver_override"
        test -w $orfile
            check_status "access denied to $orfile"
        test -w $bindfile
            check_status "can not bind $pcibdf to $driver"
        echo "$driver" > $orfile
        echo "$pcibdf" > $bindfile
    fi
done
########################################################################
if [ "$optVerify" != "" ] && [ ${#faillist[@]} -gt 0 ]; then
    echo "FAIL: ${faillist[@]}"
    exit -1
fi
########################################################################
exit 0
