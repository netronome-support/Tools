#!/bin/bash

########################################################################
function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}
########################################################################
##  Check for required tools

which virsh > /dev/null 2>&1
    check_status "'virsh' is not installed"

########################################################################
tmpdir=$(mktemp --directory)
########################################################################
export VIRSH_IFACE_IGNORE_STATE='yes'
########################################################################
# Any command in a pipeline must trigger an error:
set -o pipefail

vm_name_list=$( ( virsh list --all \
    | tail -n +3 \
    | sed -rn 's/^\s*(\S+)\s+(\S+)\s+.*$/\2/p' ) )

for vmname in ${vm_name_list[@]} ; do
    if_list_file="$tmpdir/$vmname-iflist.txt"
    virsh dumpxml $vmname \
        | tr -d '\n' \
        | sed -r 's/(<interface)/\n\1/g' \
        | sed -r 's/(\/interface>)/\1\n/g' \
        | grep -E "^<interface type='(network|bridge)'" \
        > $if_list_file
        check_status "failed to scan VM for interfaces"
    ifcnt=$(wc --lines $if_list_file | cut -d ' ' -f 1)
    for ifidx in $(seq 1 $ifcnt) ; do
        if_xml=$(cat $if_list_file \
            | head -$ifidx \
            | tail -1)
        if_type=$(echo $if_xml | sed -rn "s/^.*interface type='(\S+)'.*\$/\1/p")
        if_hwaddr=$(echo $if_xml | sed -rn "s/^.*mac address='(\S+)'.*\$/\1/p")
        if_network=$(echo $if_xml | sed -rn "s/^.*network='(\S+)'.*\$/\1/p")
        if_bridge=$(echo $if_xml | sed -rn "s/^.*bridge='(\S+)'.*\$/\1/p")
        export VIRSH_IFACE_NETWORK_TYPE="$if_type"
        export VIRSH_IFACE_NETWORK_NAME="$if_network"
        export VIRSH_IFACE_BRIDGE_NAME="$if_bridge"
        if_ipaddr=$(virsh-get-vm-ipaddr.sh $vmname 2>&1)
        if [ $? -ne 0 ]; then
            if_ipaddr=""
        fi
        if [ "$if_network" != "" ]; then
            if_network="'$if_network'"
        fi
        printf "  %-24s %-17s  %-8s %-10s %-10s %-10s %s\n" \
            "$vmname" "$if_hwaddr" \
            "$if_type" "$if_network" "$if_bridge" "$if_ipaddr"
    done
done

########################################################################
rm -rf $tmpdir
########################################################################
exit 0
