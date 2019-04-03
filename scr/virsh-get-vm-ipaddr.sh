#!/bin/bash

vmname="$1"

########################################################################
#
#  Extract IPv4 address from a network interface of a VM.
#  This is based on the DHCP lease database of libvirt.
#
########################################################################

: ${VIRSH_MGMT_SSH_PORT:='22'}

########################################################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}

########################################################################
# Any command in a pipeline must trigger an error:
set -o pipefail

########################################################################
##  Check command argument

test "$vmname" != ""
    check_status "please specify VM name"

########################################################################
##  Check for required tools

which virsh > /dev/null 2>&1
    check_status "'virsh' is not installed"

which nc > /dev/null 2>&1
    check_status "'nc' is not installed"

########################################################################
##  Check that VM exists and is running

virsh dominfo $vmname > /dev/null 2>&1
    check_status "VM '$vmname' does not exist"

state=$(virsh dominfo $vmname \
    | sed -rn 's/^State:\s+(\S+)$/\1/p')

test "$state" == "running"
    check_status "VM '$vmname' is not running"

########################################################################
##  Extract the MAC address of the management interface from XML

iflist=$(mktemp /tmp/.interfaces-XXXXX.xml)

ss=""
if [ "$VIRSH_IFACE_NETWORK_TYPE" != "" ]; then
    ss="${ss}s/^(.*interface type='$VIRSH_IFACE_NETWORK_TYPE'.*)\$/\1/p;"
fi
if [ "$VIRSH_IFACE_NETWORK_NAME" != "" ]; then
    ss="${ss}s/^(.*network='$VIRSH_IFACE_NETWORK_NAME'.*)\$/\1/p;"
fi
if [ "$VIRSH_IFACE_BRIDGE_NAME" != "" ]; then
    ss="${ss}s/^(.*bridge='$VIRSH_IFACE_BRIDGE_NAME'.*)\$/\1/p;"
fi

#vm_iface_mac_addr=$(
virsh dumpxml $vmname \
    | tr -d '\n' \
    | sed -r 's/(<interface)/\n\1/g' \
    | sed -r 's/(\/interface>)/\1\n/g' \
    | grep -E "^<interface type='(network|bridge)'" \
    | sed -nr "$ss" \
    > $iflist
    check_status "failed to scan VM for interfaces"

# Count how many interfaces there are
ifcnt=$(wc --lines $iflist | cut -d ' ' -f 1)

if [ $ifcnt -gt 1 ]; then
    sed -rn "s/^(.*='default'.*)\$/\1/p" \
        -i  $iflist
    ifcnt=$(wc --lines $iflist | cut -d ' ' -f 1)
fi

test $ifcnt -eq 1
    check_status "could not find the interfece on VM '$vmname'"

vm_iface_mac_addr=$(cat $iflist \
    | sed -rn "s/^.*mac\saddress='(\S+)'.*\$/\1/p")
vm_iface_network_name=$(cat $iflist \
    | sed -rn "s/^.*\snetwork='(\S+)'\s.*\$/\1/p")

: ${vm_iface_network_name:=default}

rm -f $iflist

test "$vm_iface_mac_addr" != ""
    check_status "failed to extract MAC address from VM '$vmname'"

########################################################################

virsh net-dhcp-leases $vm_iface_network_name > /dev/null 2>&1
if [ $? -eq 0 ]; then
    # Get the IP address from the correct DHCP lease
    ipaddr=$(virsh net-dhcp-leases $vm_iface_network_name \
        | gawk '{ print $3" "$5" "$6 }' \
        | grep -E "^$vm_iface_mac_addr " \
        | cut -d ' ' -f 2 \
        | cut -d '/' -f 1 \
        )
else
    lfile="/var/lib/libvirt/dnsmasq/$vm_iface_network_name.leases"
    test -f $lfile
        check_status "'virsh net-dhcp-leases' not supported"

    ipaddr=$(cat $lfile \
        | grep -E " $vm_iface_mac_addr " \
        | cut -d ' ' -f 3 \
        )
fi

########################################################################

test "$ipaddr" != ""
    check_status "no active lease for $vm_iface_mac_addr on $vmname"

########################################################################
##  Verify that VM is responding to SSH

nc -w 1 $ipaddr $VIRSH_MGMT_SSH_PORT < /dev/null > /dev/null 2>&1
    check_status "VM '$vmname' is not responding on port $VIRSH_MGMT_SSH_PORT (SSH)"

########################################################################

echo $ipaddr
exit 0
