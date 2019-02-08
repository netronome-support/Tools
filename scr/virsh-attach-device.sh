#!/bin/bash

########################################
function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}
########################################
re_integer='^[0-9]+$'
re_nfp_repr='^nfp_v[01]\.[0-9]{1,2}$'
xdig="[0-9abcdefABCDEF]"
########################################
param=""
for arg in "$@" ; do
  if [ "$param" == "" ]; then
    case "$arg" in
      "--help"|"-h")
        echo "Start VM(s)"
        echo "  --help -h"
        echo "  --verbose -v"
        echo "  --vm-name <name>"
        echo "  --type xvio|sr-iov|hostdev|bridge"
        echo "  --hw-addr <MAC address>"
        echo "  --pci-addr <PCI address>"
        echo "  --eth-801q-vid <integer>"
        echo "  --nfp-vf-index <integer>"
        echo "  --nfp-vf-repr <ifname>"
        echo "  --xvio-socket <socket file>"
        echo "  --queues <integer>"
        exit
        ;;
      "--verbose"|"-v")         optVerbose="yes" ;;
      "--vm-name")              param="$arg" ;;
      "--type")                 param="$arg" ;;
      "--hw-addr")              param="$arg" ;;
      "--pci-addr")             param="$arg" ;;
      "--eth-801q-vid")         param="$arg" ;;
      "--nfp-vf-index")         param="$arg" ;;
      "--nfp-vf-repr")          param="$arg" ;;
      "--xvio-socket")          param="$arg" ;;
      "--queues")               param="$arg" ;;
      *)
        echo "ERROR: Failed to parse '$arg'"
        echo "Full command line: $@"
        exit -1
        ;;
    esac
  else
    case "$param" in
      "--vm-name")              vmname="$arg" ;;
      "--type")                 type="$arg" ;;
      "--hw-addr")              hw_addr="$arg" ;;
      "--pci-addr")             pci_addr="$arg" ;;
      "--eth-801q-vid")         eth_801q_vid="$arg" ;;
      "--nfp-vf-index")         nfp_vf_index="$arg" ;;
      "--nfp-vf-repr")          nfp_vf_repr_iface="$arg" ;;
      "--xvio-socket")          xvio_socket="$arg" ;;
      "--queues")               queues="$arg" ;;
    esac
    param=""
  fi
done
########################################
tmpdir=$(mktemp --directory)
logdir="/var/log"
logfile="$logdir/virsh-attach-device.log"
########################################
test "$vmname" != ""
    check_status "VM name is not specified"
which virsh > /dev/null 2>&1
    check_status "'virsh' is not installed (libvirt-bin package)"

########################################
if [ "$nfp_vf_index" != "" ]; then
    [[ "$nfp_vf_index" =~ $re_integer ]]
        check_status "NFP VF index is not an integer ($nfp_vf_index)"
    test $nfp_vf_index -lt 60
        check_status "NFP VF index must not exceed 59"
fi
########################################
if [ "$nfp_vf_repr_iface" != "" ]; then
    grep -E "^\s*${nfp_vf_repr_iface}:" /proc/net/dev > /dev/null
        check_status "interface does not exist ($nfp_vf_repr_iface)"
    which ethtool  > /dev/null 2>&1
        check_status "'ethtool' is not installed"
    ethtool -i $nfp_vf_repr_iface > $tmpdir/iface.info
        check_status "failed to fetch info about $nfp_vf_repr_iface"
    driver=$(cat $tmpdir/iface.info \
        | sed -rn 's/^driver:.*\s(\S+)$/\1/p')
    pci_addr=$(cat $tmpdir/iface.info \
        | sed -rn 's/^bus-info:.*\s(\S+)$/\1/p')
    nfp_vf_index=$(echo $nfp_vf_repr_iface \
        | sed -rn 's/nfp_v[01]\.([0-9]+)$/\1/p')
fi
########################################
if [ "$xvio_socket" == "" ] && [ "$nfp_vf_index" != "" ]; then
    VIRTIOFWD_SOCKET_DIR="/tmp/virtio-forwarder"
    if [ -f /etc/default/virtioforwarder ]; then
        dirname=$(cat /etc/default/virtioforwarder \
            | sed -rn 's/^VIRTIOFWD_SOCKET_DIR=(\S+)$/\1/p' \
            | tail -1)
        if [ "$dirname" != "" ] && [ -d "$dirname" ]; then
            VIRTIOFWD_SOCKET_DIR="$dirname"
        fi
    fi
    xvio_socket="$VIRTIOFWD_SOCKET_DIR/virtio-forwarder$nfp_vf_index.sock"
fi
########################################
virsh dominfo "$vmname" > $tmpdir/status.info 2>&1
    check_status "VM '$vmname' does not exist"
vm_state=$(cat $tmpdir/status.info \
    | sed -rn 's/^State:\s+(\S.*)$/\1/p')
########################################
xml=""
########################################
case $type in
  "xvio"|"XVIO")
    devtype="interface"
    devopts="type='vhostuser'"
    test "$xvio_socket" != ""
        check_status "XVIO socket not specified"
    test -S "$xvio_socket"
        check_status "XVIO socket '$xvio_socket' missing"
    xml="$xml <source type='unix' path='$xvio_socket' mode='client'/>"
    xml="$xml <model type='virtio'/>"
    ;;
  "hostdev")
    devtype="hostdev"
    devopts="mode='subsystem' type='pci' managed='yes'"
    xml="$xml <driver name='vfio'/>"
    require_pci_addr=YES
    pci_dev_driver="vfio-pci"
    ;;
  "sr-iov"|"SR-IOV")
    devtype="interface"
    devopts="type='hostdev' managed='yes'"
    require_pci_addr=YES
    pci_dev_driver="vfio-pci"
    ;;
  "bridge")
    devtype="interface"
    devopts="type='bridge'"
    bridx=$(echo "$brname" | tr -d '[:alpha:]' | tr -d '-')
    vmidx=$(echo "$vmname" | tr -d '[:alpha:]' | tr -d '-')
    ifname="port-$bridx-$vmidx"
    xml="$xml <source bridge='$brname'/>"
    xml="$xml <virtualport type='openvswitch'/>"
    xml="$xml <target dev='$ifname'/>"
    xml="$xml <model type='virtio'/>"
    ;;
  *)
    false ; check_status "device type (--type) not specified"
esac
########################################
if [ "$require_pci_addr" != "" ] && [ "$pci_addr" == "" ]; then
    test "$nfp_vf_index" != ""
        check_status "missing PCI address for device"
    nfp_pci_bus=$(lspci -d 19ee: \
        | head -1 \
        | cut -d ' ' -f 1 \
        | sed -r "s/:${xdig}{2}.${xdig}\$//")
    printf -v pci_addr "%s:%02x.%u" "$nfp_pci_bus" \
        $(( 8 + nfp_vf_index / 8 )) \
        $(( nfp_vf_index % 8 ))
    # Attach the appropriate device driver
    which set-device-driver.sh
        check_status "missing script 'set-device-driver.sh'"
    set-device-driver.sh --driver "$pci_dev_driver" "$pci_addr" \
        || exit -1
fi
########################################
if [ "$hw_addr" != "" ]; then
    xdp='[0-9a-fA-F]{2}' # Hexadecimal Digit Pair
    re_hwaddr="^${xdp}:${xdp}:${xdp}:${xdp}:${xdp}:${xdp}\$"
    [[ "$hw_addr" =~ $re_hwaddr ]]
        check_status "could not parse HW address '$hw_addr'"
    xml="$xml <mac address='$hw_addr'/>"
fi
########################################
if [ "$queues" != "" ]; then
    [[ "$queues" =~ $re_integer ]]
        check_status "could not parse '--queues $queues'"
    test $queues -lt 1
        check_status "number of queues must be at least '1'"
    if [ $queues -gt 1 ]; then
        xml="$xml <driver name='vhost' queues='$queues'/>"
    fi
fi
########################################
if [ "$eth_801q_vid" != "" ]; then
    xml="$xml <vlan> <tag id='$eth_801q_vid'/> </vlan>"
fi
########################################
if [ "$pci_addr" != "" ]; then
    # Format "0000:00:00.0"
    fmt0="(${xdig}+):(${xdig}+):(${xdig}+)\.(${xdig})"
    # Format "00:00.0"
    fmt1="(${xdig}+):(${xdig}+)\.(${xdig})"
    bdf0_sp=$(echo $pci_addr \
        | sed -rn 's/^'"${fmt0}"'$/\1 \2 \3 \4/p')
    bdf1_sp=$(echo $pci_addr \
        | sed -rn 's/^'"${fmt1}"'$/0 \1 \2 \3/p')
    if [ "$bdf0_sp" != "" ] ; then
        bdf_sp="$bdf0_sp"
    elif [ "$bdf1_sp" != "" ] ; then
        bdf_sp="$bdf1_sp"
    else
        echo "ERROR: could not parse PCI BDF $pci_addr"
        exit -1
    fi

    printf -v addr \
        "domain='0x%04x' bus='0x%02x' slot='0x%02x' function='%x'" \
        0x$(echo $bdf_sp | cut -d ' ' -f 1) \
        0x$(echo $bdf_sp | cut -d ' ' -f 2) \
        0x$(echo $bdf_sp | cut -d ' ' -f 3) \
        0x$(echo $bdf_sp | cut -d ' ' -f 4)
    xml="$xml <source><address type='pci' $addr /></source>"
fi
########################################
xml="<$devtype $devopts> $xml </$devtype>"
########################################
xmlfile="$tmpdir/device.xml"
echo "$xml" > $xmlfile
########################################
##  Compose 'virsh' command line
cmd=( "virsh" "attach-device" )
cmd+=( "$vmname" )
cmd+=( "$xmlfile" )
cmd+=( "--config" )
if [ "$vm_state" == "running" ]; then
    cmd+=( "--live" )
fi
########################################
cat <<EOF >> $logfile

# $(date)
CMD: ${cmd[@]}
XML: $xml

EOF
########################################
capfile="$tmpdir/attach.log"

##  Run the 'virsh attach-device' command:
${cmd[@]} > $capfile 2>&1

if [ $? -ne 0 ]; then
    echo "ERROR($(basename $0)): virsh attach-device failed"
    echo "XML: $xml"
    cat $capfile | tee -a $logfile
    echo
    exit -1
fi

cat $capfile >> $logfile

########################################
rm -rf $tmpdir
########################################
exit 0
