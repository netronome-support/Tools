#!/bin/bash

########################################
# This script is maintained at:
#   https://github.com/netronome-support/Tools
########################################
function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}
########################################
set -o pipefail
########################################
re_integer='^[0-9]+$'
xdig="[0-9abcdefABCDEF]"
model_type="virtio"
source_mode="client"
########################################
param=""
: ${nfp_dev_idx:='0'}
for arg in "$@" ; do
  if [ "$param" == "" ]; then
    case "$arg" in
      "--help"|"-h")
        echo "Attach device/interface to VM"
        echo "Syntax: $(basename $0) [<options>]"
        echo "Mandatory:"
        echo "  --vm-name <name>"
        echo "  --type xvio|sr-iov|hostdev|bridge"
        echo "Options:"
        echo "  --help -h"
        echo "  --hw-addr <MAC address>"
        echo "  --pci-addr <PCI address>"
        echo "  --eth-801q-vid <integer>"
        echo "  --nfp-idx <integer>"
        echo "  --nfp-vf-index <integer>"
        echo "  --nfp-vf-repr <ifname>"
        echo "  --br-name <bridge name>"
        echo "  --ovs-br-name <bridge name>"
        echo "  --ovs-port-name <ifname>"
        echo "  --target-dev-name <target device name>"
        echo "  --guest-pci-slot <index>"
        echo "  --model-type <interface type>"
        echo "  --source-mode server|client"
        echo "  --socket <socket file>"
        echo "  --queues <integer>"
        exit
        ;;
      "--verbose"|"-v")         optVerbose="yes" ;;
      "--vm-name")              param="$arg" ;;
      "--type")                 param="$arg" ;;
      "--hw-addr")              param="$arg" ;;
      "--pci-addr")             param="$arg" ;;
      "--eth-801q-vid")         param="$arg" ;;
      "--nfp-dev-idx")          param="$arg" ;;
      "--nfp-vf-index")         param="$arg" ;;
      "--nfp-vf-repr")          param="$arg" ;;
      "--br-name")              param="$arg" ;;
      "--ovs-br-name")          param="$arg" ;;
      "--ovs-port-name")        param="$arg" ;;
      "--target-dev-name")      param="$arg" ;;
      "--guest-pci-slot")       param="$arg" ;;
      "--model-type")           param="$arg" ;;
      "--source-mode")          param="$arg" ;;
      "--xvio-socket")          param="--socket" ;;
      "--socket")               param="$arg" ;;
      "--queues")               param="$arg" ;;
      *)
        echo "ERROR($(basename $0)): failed to parse '$arg'"
        echo "Full command line: $0 $@"
        exit -1
        ;;
    esac
  else
    case "$param" in
      "--vm-name")              vmname="$arg" ;;
      "--type")                 type="${arg,,}" ;; # Lower-Case
      "--hw-addr")              hw_addr="$arg" ;;
      "--pci-addr")             pci_addr="$arg" ;;
      "--eth-801q-vid")         eth_801q_vid="$arg" ;;
      "--nfp-dev-idx")          nfp_dev_idx="$arg" ;;
      "--nfp-vf-index")         nfp_vf_index="$arg" ;;
      "--nfp-vf-repr")          nfp_vf_repr_iface="$arg" ;;
      "--br-name")              br_name="$arg" ;;
      "--ovs-br-name")          ovs_br_name="$arg" ;;
      "--ovs-port-name")        ovs_port_name="$arg" ;;
      "--target-dev-name")      target_dev_name="$arg" ;;
      "--guest-pci-slot")       guest_pci_slot="$arg" ;;
      "--model-type")           model_type="$arg" ;;
      "--source-mode")          source_mode="$arg" ;;
      "--socket")               socket_fname="$arg" ;;
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
if [ "$socket_fname" == "" ] && [ "$nfp_vf_index" != "" ]; then
    VIRTIOFWD_SOCKET_DIR="/tmp/virtio-forwarder"
    if [ -f /etc/default/virtioforwarder ]; then
        dirname=$(cat /etc/default/virtioforwarder \
            | sed -rn 's/^VIRTIOFWD_SOCKET_DIR=(\S+)$/\1/p' \
            | tail -1)
        if [ "$dirname" != "" ] && [ -d "$dirname" ]; then
            VIRTIOFWD_SOCKET_DIR="$dirname"
        fi
    fi
    socket_fname="$VIRTIOFWD_SOCKET_DIR/virtio-forwarder$nfp_vf_index.sock"
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
  "xvio"|"hostdev"|"sr-iov"|"vhostuser"|"direct") ;;
  "sriov"|"vf"|"pf")    type="sr-iov" ;;
  "bridge")             type="bridge" ; br_type="" ;;
  "ovs"|"ovs-bridge")   type="bridge" ; br_type="ovs" ;;
  *)
    false ; check_status "device type (--type) not specified"
esac
########################################
case $type in
  "xvio")
    devtype="interface"
    devopts="type='vhostuser'"
    test "$socket_fname" != ""
        check_status "XVIO socket not specified"

    # After a restart of the virtio-forwarder, it may take some time for
    # the socket file to appear. Thus give it some time:
    sec_cnt_start=$(date +'%s')
    sec_cnt_limit=$(( sec_cnt_start + 10 ))
    while [ ! -S "$socket_fname" ]; do
        sleep 0.25
        sec_cnt_now=$(date +'%s')
        test $sec_cnt_now -lt $sec_cnt_limit
            check_status "missing socket file '$socket_fname'"
    done

    xml="$xml <source type='unix' path='$socket_fname' mode='$source_mode'/>"
    xml="$xml <model type='virtio'/>"
    # Although XVIO attaches to a socket, the driver on the VF needs
    # to be set to 'igb_uio'
    require_pci_addr=YES
    pci_dev_driver="vfio-pci"
    ;;
  "vhostuser")
    devtype="interface"
    devopts="type='vhostuser'"
    require_socket_fname=YES
    xml="$xml <source type='unix' path='$socket_fname' mode='$source_mode'/>"
    xml="$xml <model type='$model_type'/>"
    ;;
  "hostdev")
    devtype="hostdev"
    devopts="mode='subsystem' type='pci' managed='yes'"
    xml="$xml <driver name='vfio'/>"
    require_pci_addr=YES
    pci_dev_driver="vfio-pci"
    ;;
  "sr-iov")
    devtype="interface"
    devopts="type='hostdev' managed='yes'"
    require_pci_addr=YES
    pci_dev_driver="vfio-pci"
    ;;
  "direct")
    devtype="interface"
    devopts="type='direct'"
    xml="$xml <source dev='$br_name' mode='bridge'/>"
    if [ "$target_dev_name" != "" ]; then
        xml="$xml <target dev='$target_dev_name'/>"
    fi
    xml="$xml <model type='$model_type'/>"
    test "$br_name" != ""
        check_status "please specify bridge name"
    ;;
  "bridge")
    if [ "$ovs_br_name" != "" ]; then
        br_type="ovs"
        br_name="$ovs_br_name"
    fi
    devtype="interface"
    devopts="type='bridge'"
    if [ "$br_type" == "ovs" ]; then
        xml="$xml <virtualport type='openvswitch'/>"
    fi
    test "$br_name" != ""
        check_status "no bridge name specified"
    xml="$xml <source bridge='$br_name'/>"
    if [ "$ovs_port_name" != "" ]; then
        xml="$xml <target dev='$ovs_port_name'/>"
    fi
    xml="$xml <model type='$model_type'/>"
    ;;
esac
########################################
if [ "$require_pci_addr" != "" ] && [ "$pci_addr" == "" ]; then
    nfp_pci_list=( $(lspci -d 19ee: -s '00.0' \
        | cut -d ' ' -f 1 ) )
    test ${#nfp_pci_list[@]} -gt 0
        check_status "there is no NFP detected on the PCI bus"
    if [[ ! "$nfp_dev_idx" =~ $re_integer ]]; then
        false ; check_status "NFP index is not an integer ($nfp_dev_idx)"
    fi
    nfp_pci_addr="${nfp_pci_list[$nfp_dev_idx]}"
    test "$nfp_pci_addr" != ""
        check_status "there is no NFP with index $nfp_dev_idx"
    pci_fmt="(.*$xdig{2}):$xdig{2}\.$xdig"
    nfp_pci_bus=$(echo $nfp_pci_addr \
        | sed -r "s/^.*${pci_fmt}\$/\1/")
    test "$nfp_pci_bus" != ""
        check_status "failed to extract 'bus' from $nfp_pci_addr"
    test "$nfp_vf_index" != ""
        check_status "missing PCI address for device"
    printf -v pci_addr "%s:%02x.%u" "$nfp_pci_bus" \
        $(( 8 + nfp_vf_index / 8 )) \
        $(( nfp_vf_index % 8 ))
fi
########################################
if [ "$require_socket_fname" != "" ]; then
    test "$socket_fname" != ""
        check_status "socket file must be specified"
    test -S "$socket_fname"
        check_status "not a socket file ($socket_fname)"
    chmod a+rwx $socket_fname
        check_status "failed to change permissions on $socket_fname"
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
if [ "$guest_pci_slot" != "" ]; then
    [[ "$guest_pci_slot" =~ $re_integer ]]
        check_status "could not parse guest PCI bus number '$guest_pci_slot'"
    printf -v slot_hex "0x%02x" $guest_pci_slot
    xml="$xml <address type='pci' bus='0x00' slot='$slot_hex' function='0'/>"
fi
########################################
if [ "$queues" != "" ]; then
    [[ "$queues" =~ $re_integer ]]
        check_status "could not parse '--queues $queues'"
    test $queues -ge 1
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
        false ; check_status "could not parse PCI BDF $pci_addr"
    fi

    if [ "$pci_dev_driver" != "" ]; then
        which set-device-driver.sh > /dev/null 2>&1
            check_status "missing script 'set-device-driver.sh'"
        set-device-driver.sh --driver "$pci_dev_driver" "$pci_addr" \
            || exit -1
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
: ${VIOFWD_TOOL_DIR:=/usr/lib/virtio-forwarder}
: ${VIOFWD_PORT_CTRL:=$VIOFWD_TOOL_DIR/virtioforwarder_port_control.py}

if [ "$type" == "xvio" ]; then
    test -x "$VIOFWD_PORT_CTRL"
        check_status "virtio-forwarder port control tool missing"

    $VIOFWD_PORT_CTRL add \
        --pci-addr "$pci_addr" --virtio-id "$nfp_vf_index"
        check_status "faild to attach VIOFWD port"
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
    echo "CMD: ${cmd[*]}"
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
