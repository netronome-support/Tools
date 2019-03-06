#!/bin/bash

########################################################
# Optional Items:
# SYS_INV_CAPTURE_ETHTOOL_DUMPS=yes
########################################################
tmpdir=$(mktemp --directory)
capname="capture-$(date +'%Y-%m-%d-%H%M')"
capdir="$tmpdir/$capname"
mkdir -p $capdir
########################################################
function f_mkdir () {
    local dname="$1"
    mkdir --mode 755 -p $capdir/$dname
    if [ $? -ne 0 ]; then
        echo "WARNING: failed to create $capdir/$dname"
    fi
}

########################################################
if [ "$(whoami)" != "root" ]; then
    echo "WARNING: for best result, please run this as 'root'"
fi
if ! which ethtool > /dev/null 2>&1; then
    SYS_INV_CAPTURE_ETHTOOL_DUMPS=
fi
########################################################
# Copy system files

list=()
list+=( "/etc/hostname" )
list+=( "/etc/*-release" )
list+=( "/etc/network" )
list+=( "/etc/sysconfig/network-scripts/ifcfg*" )
list+=( "/etc/networks" )
list+=( "/etc/NetworkManager/conf.d" )
list+=( "/etc/hosts" )
list+=( "/etc/fstab" )
list+=( "/etc/netronome.conf" )
list+=( "/etc/timezone" )
list+=( "/etc/grub" )
list+=( "/etc/irqbalance" )
list+=( "/etc/libvirt-bin" )
list+=( "/etc/rc.local" )
list+=( "/etc/modules" )
list+=( "/etc/modprobe.d" )

list+=( "/boot/grub/grub.cfg" )
list+=( "/boot/grub2/grub.cfg" )
list+=( "/boot/grub/grubenv" )
list+=( "/boot/grub2/grubenv" )

list+=( $(find /boot -name "config*$(uname -r)*") )

list+=( "/etc/default/irqbalance" )

list+=( "/etc/apparmor.d/abstractions/libvirt-qemu" )

list+=( "/proc/cmdline" )
list+=( "/proc/interrupts" )
list+=( "/proc/meminfo" )
list+=( "/proc/mounts" )
list+=( "/proc/uptime" )
list+=( "/proc/version" )
list+=( "/proc/vmstat" )
list+=( "/proc/net/dev" )

list+=( "/var/log/upstart/networking.log" )
list+=( "/var/log/upstart/virtiorelayd.log" )
list+=( "/var/log/upstart/network-interface-*.log" )
list+=( "/var/log/upstart/kmod.log" )

list+=( "/sys/module/nfp_offloads/control/rh_entries" )

list+=( "/sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages" )
list+=( "/sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages" )

# Save the script itself into the capture
list+=( "$0" )

########################################################
# Determine NFP-related parameters
nfp_access_iface_list=()
nfp_drv_dir="/sys/bus/pci/drivers/nfp"
if [ -d $nfp_drv_dir ]; then
    nfplist=$(find $nfp_drv_dir -type l -name '*:*:*.*')
    for nfpdir in $nfplist ; do
        list+=( "$nfpdir/numa_node" )
        list+=( "$nfpdir/irq" )
        if [ -d $nfpdir/net ]; then
            nfp_if_dir=$(find $nfpdir/net -maxdepth 1 -mindepth 1 -type d | head -1)
            if [ -d $nfp_if_dir ]; then
                nfp_access_iface_list+=( $(basename $nfp_if_dir) )
            fi
        fi
    done
fi

########################################################
copy="/bin/cp --recursive --parents --dereference"
copy="$copy --target-directory $capdir"

for fname in "${list[@]}" ; do
    if [[ "${fname/*\**/}" == "" ]]; then
        # If 'fname' contains a wildcard '*':
        path=$(echo "$fname" | sed -rn 's#^(\S+)/.*$#\1#p')
        filt=$(echo "$fname" | sed -rn 's#^\S+/(.*)$#\1#p')
        if [ -d "$path" ]; then
            flist="$(find $path -name $filt)"
            for fname in $flist ; do
                $copy "$fname"
            done
        else
            echo "Missing $path" >> $capdir/missing-files.txt
        fi
    elif [ -e "$fname" ]; then
        if [ -r "$fname" ]; then
            $copy "$fname"
        else
            echo "Access denied: $fname" >> $capdir/missing-files.txt
        fi
    else
        echo "Missing $fname" >> $capdir/missing-files.txt
    fi
done

########################################################

function run () {
    local cmd="$1"
    local args="$2"
    local fname="$3"
    rc=""
    if [ -x $cmd ]; then
        local tool="$cmd"
    else
        local tool=$(which $cmd 2> /dev/null)
        if [ ! -x "$tool" ]; then
            echo "Missing $cmd" >> $capdir/missing-tools.txt
            return
        fi
    fi
    printf "\n-- %s  -  %s\n# %s %s > %s\n" \
        "$(date +'%Y-%m-%d %H%M%S.%N')" "$cmd" \
        "$tool" "$args" "$fname" \
        >> $capdir/cmd.log
    if [ "$fname" == "" ]; then
        local capfile="/dev/null"
    else
        local dirname=$(dirname "$fname")
        if [ "$dirname" != "" ] && [ "$dirname" != "." ]; then
            f_mkdir $dirname
        fi
        local capfile="$capdir/$fname"
    fi
    $tool $args > $capfile 2>> $capdir/cmd.log
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "  ERROR Code: $rc" \
            >> $capdir/cmd.log
    fi
}

########################################################
# Create list of available NFPs

nfp_pf_bdf_list=( $(lspci -d 19ee: \
    | cut -d ' ' -f 1 \
    | sed -rn 's/(:00\.0)$/\1/p' ) )
nfpidx=0
nfp_idx_list=()
for bdf in ${nfp_pf_bdf_list[@]} ; do
    run "nfp-nsp" "-N -n $nfpidx" "nfp-$nfpidx/nsp-no-op.txt"
    if [ "$rc" == "0" ]; then
        nfp_idx_list+=( $nfpidx )
    fi
    nfpidx=$(( nfpidx + 1 ))
done

########################################################

function sample () {
    local name="$1"

    # Note: timing is captured in the 'cmd.log' file

    run "ifconfig" "-a"             "$name/ifconfig.txt"
    run "netstat" "-s"              "$name/netstat-s.txt"
    run "ovs-ctl" "status troubleshoot -C" \
        "$name/ovs-ctl-status-troubleshoot.txt"
    if [ "$(pgrep virtiorelayd)" != "" ]; then
        run "/opt/netronome/bin/virtio_relay_stats" "" \
            "$name/virtio-relay-stats.txt"
        run "/usr/lib/virtio-forwarder/virtioforwarder_stats.py" "" \
            "$name/virtio-forwarder-stats.txt"
    fi

    # Contrail vRouter Statistics
    run "vif" "--list" "vrouter/$name/vif-list.txt"
    run "dropstats" "" "vrouter/$name/dropstats.txt"
    run "vrfstats" "--dump" "vrouter/$name/vrfstats-dump.txt"
    run "/opt/netronome/libexec/nfp-vr-syscntrs.sh" "" \
        "vrouter/$name/nfp-vr-syscntrs.txt"

    if [ "$SYS_INV_CAPTURE_ETHTOOL_DUMPS" != "" ]; then
        # Collect Debug Information
        for ifname in ${nfp_access_iface_list[@]} ; do
            # Set Debug-Level to '1'
            run "ethtool" "--set-dump $ifname 1" ""
            fname="$capdir/$name/ethtool-dump-$ifname-l1.data"
            run "ethtool" "--get-dump $ifname data $fname" ""
        done
    fi
}

########################################################

iflist=$(cat /proc/net/dev \
    | sed -rn 's/^\s*(\S+):.*$/\1/p')

########################################################
# Try some of the tools (if installed) from:
#   http://github.com/netronome-support/Tools

run "rate" "--once --long --interval 1 --pktsize $iflist" "rate.txt"

run "list-iface-info.sh" "" "iface-info.txt"

########################################################

sample "s1"

########################################################

if [ -d /opt/netronome/bin ]; then
    export PATH="$PATH:/opt/netronome/bin"
fi

########################################################

run "whoami" ""                 "whoami.txt"
run "uname" "-r"                "kernel-version.txt"
run "uname" "-a"                "uname-all.txt"
run "lscpu" ""                  "lscpu.txt"
run "cpuid" ""                  "cpuid.txt"
run "lspci" ""                  "lspci.txt"
run "lspci" "-vvv"              "lspci-vvv.txt"
run "lspci" "-x"                "lspci-x.txt"
run "yum" "list"                "yum-list.txt"
run "dpkg" "--get-selections"   "dpkg-get-selections.txt"
run "dpkg" "-l"                 "dpkg-l.txt"
run "ip" "link list"            "ip/ip-link-list.txt"
run "ip" "addr list"            "ip/ip-addr-list.txt"
run "ip" "route list"           "ip/ip-route-list.txt"
run "ip" "neigh list"           "ip/ip-neigh-list.txt"
run "arp" "-n"                  "ip/arp-n.txt"
run "route" "-n"                "ip/route-n.txt"
run "lsmod" ""                  "lsmod.txt"
run "ps" "aux"                  "ps-aux.txt"
run "dmidecode" ""              "dmidecode.txt"
run "lshw" ""                   "lshw.txt"
run "printenv" ""               "printenv.txt"

run "virsh" "--version"         "virsh-version.txt"
run "kvm" "--version"           "kvm-version.txt"
run "/usr/libexec/qemu-kvm" "--version" "qemu-kvm-version.txt"
run "qemu-system-x86_64" "--version" "qemu-system-version.txt"

run "getenforce" "" "selinux-getenforce.txt"

run "ovs-ctl" "version"         "ovs/ovs-version.txt"
run "ovs-ctl" "status"          "ovs/ovs-status.txt"

# Netronome NFP BSP Commands
for nfpidx in ${nfp_idx_list[@]} ; do
    run "nfp-hwinfo" "-n $nfpidx"           "nfp-$nfpidx/hwinfo.txt"
    run "nfp-media" "-n $nfpidx"            "nfp-$nfpidx/media.txt"
    run "nfp-programmables" "-n $nfpidx"    "nfp-$nfpidx/programmables.txt"
    run "nfp-arm" "-D -n $nfpidx"           "nfp-$nfpidx/arm-D.txt"
    run "nfp-phymod" "-n $nfpidx"           "nfp-$nfpidx/phymod.txt"
    run "nfp-res" "-L -n $nfpidx"           "nfp-$nfpidx/locks.txt"
    run "nfp-support" "-n $nfpidx"          "nfp-$nfpidx/support.txt"
    run "nfp-system" "-n $nfpidx"           "nfp-$nfpidx/system.txt"
    run "nfp" "-n $nfpidx -m mac show port info 0 0" \
                                            "nfp-$nfpidx/mac-0-0.txt"
    run "nfp" "-n $nfpidx -m mac show port info 0 4" \
                                            "nfp-$nfpidx/mac-0-4.txt"
done

run "dpdk-devbind.py" "--status" "dpdk-devbind-status.txt"
run "virtio-forwarder" "--version" "virtio-forwarder-version.txt"
run "/usr/lib/virtio-forwarder/virtioforwarder_core_pinner.py" "" \
                                 "virtioforwarder_core_pinner.txt"

########################################################

nscnt=$(lspci -d 19ee: | wc -l)
if [ $nscnt -lt 1 ]; then
    echo "ERROR: card missing" > $capdir/pci-patch.txt
else
    check=$(setpci -d 19ee: 0xFFC.L | sed '2,$d')
    if [ "$check" != "ffffffff" ]; then
        echo "WARNING: patch MISSING" > $capdir/pci-patch.txt
    else
        echo "Patch Applied" > $capdir/pci-patch.txt
    fi
fi

########################################################
for pid in $(pgrep virtiorelayd) ; do
    cat /proc/$pid/cmdline \
        | tr '\0' ' ' \
        > $capdir/virtiorelayd-$pid-cmdline.txt
done

########################################################
if which virsh > /dev/null 2>&1; then
    for vmname in $(virsh list --all --name) ; do
        vmdir="$capdir/virsh/vms/$vmname"
        f_mkdir "virsh/vms/$vmname"
        virsh dumpxml $vmname > $vmdir/config.xml
        virsh dominfo $vmname > $vmdir/dominfo.txt
        virsh vcpuinfo $vmname > $vmdir/vcpuinfo.txt 2>&1
    done
    for netname in $(virsh net-list --name) ; do
        netdir="$capdir/virsh/net/$netname"
        f_mkdir "virsh/net/$netname"
        virsh net-dumpxml $netname > $netdir/config.xml
        virsh net-dhcp-leases $netname > $netdir/leases.txt
    done
fi

########################################################
f_mkdir "log"
if [ -d /var/log ]; then
    find /var/log -type f -ls \
        > $capdir/log/file-list.txt
fi
loglist=()
loglist+=( "syslog" )
loglist+=( "messages" )
loglist+=( "kern.log" )
loglist+=( "boot.log" )
for logfile in $loglist ; do
    if [ -f "/var/log/$logfile" ]; then
        cat /var/log/$logfile \
            | tail -1000 \
            > $capdir/log/$logfile-tail.txt
        cat /var/log/$logfile \
            | grep -E '(nfp|kvm|virtiorelayd|virtio-forward|vio4wd)' \
            | tail -1000 \
            > $capdir/log/$logfile-filtered-tail.txt
    fi
done

########################################################

dmesg --kernel \
    | tail -1000 \
    > $capdir/log/dmesg-kernel.log

dmesg --level err,warn \
    | tail -1000 \
    > $capdir/log/dmesg-err-warn.log

dmesg --syslog \
    | tail -1000 \
    > $capdir/log/dmesg-syslog.log

dmesg \
    | grep -E '(nfp|kvm|virtiorelayd|virtio-forward|vio4wd)' \
    | tail -1000 \
    > $capdir/log/dmesg-netronome.log

########################################################
# Capture listing of initramfs files

kvers=$(uname -r)
irflist=$(find /boot -name "init*$kvers*")
for irfname in $irflist ; do
    run "lsinitramfs" "$irfname" "$irfname.list"
done

########################################################
# Capture listing of Netronome firmware files

if [ -d /lib/firmware/netronome ]; then
    ls -lR /lib/firmware/netronome \
        > $capdir/firmware.list
fi

########################################################
# Capture Kernel Module Information

midir="$capdir/modinfo"
f_mkdir "modinfo"
modlist=$(lsmod \
    | tail -n +2 \
    | sed -rn 's/^(\S+)\s.*$/\1/p')
for modname in $modlist ; do
    modinfo $modname > $midir/$modname.info
done

########################################################
if which ethtool > /dev/null 2>&1; then
    ifdir="$capdir/ethtool"
    flaglist=()
    flaglist+=( "" )                    # Current Settings
    flaglist+=( "--driver" )            # (-i) Get Driver Information
    flaglist+=( "--show-features" )     # (-k) Show netdev feature list
    flaglist+=( "--module-info" )       # (-m) Show Module Information
    flaglist+=( "--show-channels" )     # (-l) Show Channels
    flaglist+=( "--show-rxfh" )         # (-x) Show RSS hash table
    flaglist+=( "--show-coalesce" )     # (-c) Show Coalesce
    flaglist+=( "--show-ring" )         # (-g) Show Ring Information
    f_mkdir "ethtool/info"
    f_mkdir "ethtool/stats"
    for ifname in $iflist ; do
        for flag in "${flaglist[@]}" ; do
            {   printf "\n-- 'ethtool $flag'\n"
                ethtool ${flag} $ifname
            } >> $ifdir/info/$ifname.txt 2>&1
        done
        run "ethtool" "--set-dump $ifname 0" ""
        run "ethtool" "--get-dump $ifname data /dev/stdout" \
            "ethtool/ifdata/$ifname.txt"
        run "ethtool" "-S $ifname" "ethtool/stats/$ifname.txt"
        if [ "$SYS_INV_CAPTURE_ETHTOOL_DUMPS" != "" ]; then
            dmpdir="$ifdir/dump"
            f_mkdir "ethtool/dump"
            # Set Debug-Level to '2'
            run "ethtool" "--set-dump $ifname 2" ""
            # Collect Debug Information
            fname="$dmpdir/$ifname-l2.data"
            run "ethtool" "--get-dump $ifname data $fname" ""
        fi
    done
fi

########################################################
# Capture OVS-TC flows

if which tc > /dev/null 2>&1 ; then
    f_mkdir "ovs-tc"
    for ifname in $iflist ; do
        run "tc" "-s filter show dev $ifname parent ffff:" "ovs-tc/$ifname.flows"
    done
    # Don't keep empty files
    find $capdir/ovs-tc -empty -delete
fi

########################################################
OVS=""
if which ovs-vsctl > /dev/null 2>&1 ; then
    f_mkdir "ovs"

    run "ovs-vsctl" "--version" "ovs/vsctl-version.txt"

    run "ovs-vsctl" "get Open_vSwitch . other_config" \
        "ovs/vsctl-other-config.txt"

    if ovs-vsctl show > /dev/null 2>&1 ; then
        OVS="INSTALLED"
    fi
fi

########################################################

if [ "$OVS" != "" ]; then
    run "ovs-dpctl" "dump-flows -m" "ovs/dpctl-flows.txt"

    run "ovs-appctl" "bond/list" "ovs/bond-list.txt"

    run "ovs-vsctl" "show" "ovs/vsctl-show.txt"
fi

########################################################
# Capture Link-Aggregation (bonding) Status

listfile="$capdir/bond-list.txt"
if [ -f $listfile ] && [ "$OVS" != "" ]; then
    f_mkdir "ovs/bond"
    bondlist=$(cat $listfile \
        | tail -n +2 \
        | cut -f 1)
    for bondname in $bondlist ; do
        ovs-appctl bond/show $bondname 2>&1 \
            > $capdir/ovs/bond/$bondname-bond.txt
        ovs-appctl lacp/show $bondname 2>&1 \
            > $capdir/ovs/bond/$bondname-lacp.txt
    done
fi

########################################################
if [ "$OVS" != "" ]; then
    for brname in $(ovs-vsctl list-br) ; do
        brdir="$capdir/ovs/br/$brname"
        f_mkdir "ovs/br/$brname"
        ovs-vsctl list-ports  $brname \
            > $brdir/vsctl-ports.txt
        ovs-ofctl dump-ports -O OpenFlow13 $brname \
            > $brdir/ofctl-ports.txt
        ovs-ofctl dump-ports-desc -O OpenFlow13 $brname \
            > $brdir/ofctl-ports-desc.txt
        ovs-ofctl dump-flows -O OpenFlow13 $brname \
            > $brdir/ofctl-flows.txt
        ovs-appctl fdb/show $brname \
            > $brdir/ofctl-fdb-show.txt
    done
fi

########################################################

if [ -x /opt/netronome/bin/ovs-ctl ]; then
    nfp_iface_list=$(cat /proc/net/dev\
        | sed -rn 's/^\s*(nfp_\S+):.*$/\1/p')
    for iface in $nfp_iface_list ; do
            >> $capdir/ovs-ctl-status-wire.txt
        status=$(/opt/netronome/bin/ovs-ctl status wire $iface 2> /dev/null)
        if [ $? -eq 0 ]; then
            printf "%-12s %s\n" "$iface:" "$status" \
                >> $capdir/ovs-ctl-status-wire.txt
        fi
    done
fi

########################################################
# Contrail vRouter Dataplane commands

run "vrouter" "--info" "vrouter/vrouter-info.txt"
run "contrail-status" "" "vrouter/contrail-status.txt"
run "flow" "-l" "vrouter/flow-l.txt"

########################################################

sample "s2"

########################################################
# Copy capture script

/bin/cp $0 --target-directory $capdir

########################################################

chmod u+rw --recursive $capdir

tar cz -C $tmpdir -f $HOME/$capname.tgz $capname

/bin/rm -rf $tmpdir

echo "System Inventory Capture file: $HOME/$capname.tgz"

########################################################
exit 0
