#!/bin/bash

########################################################################
##  Variable Defaults:

VM_NAME="$BUILD_VM_NAME"

########################################################################

: "${VM_BUILD_DPDK_VERSION:=19.02}"

########################################################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}

########################################################################
##  Required sub-scripts

reqscrlist=()
reqscrlist+=( "install-netronome-support-tools.sh" )
reqscrlist+=( "install-packages.sh" )
reqscrlist+=( "rsync-vm.sh" )
reqscrlist+=( "access-vm.sh" )
for reqscr in "${reqscrlist[@]}" ; do
    which $reqscr > /dev/null 2>&1
        check_status "missing script '$reqscr'"
done

########################################################################
tmpdir=$(mktemp --directory)
########################################################################

# Root File System (for upload to VM)
rfsdir="$tmpdir/rfs"
mkdir -p $rfsdir
mkdir -p $rfsdir/etc/profile.d

########################################################################
mkdir -p $rfsdir/root
touch $rfsdir/root/.hushlogin

########################################################################
##  Setup NetPlan

mkdir -p $rfsdir/etc/netplan
mkdir -p $rfsdir/etc/cloud/cloud.cfg.d
cat <<EOF > $rfsdir/etc/netplan/80-base-vm-interfaces.yaml
network:
    version: 2
    ethernets:
        id0:
            match: 
                name: en*
            dhcp4: true
            optional: true
EOF
cat <<EOF > $rfsdir/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
network: {config: disabled}
EOF

########################################################################
##  Setup Netronome Profile file

cat <<EOF > $rfsdir/etc/profile.d/ns-path.sh

# Netronome Script - adding PATH items

function add_path_after () {
    local item="$1"
    if ! echo \$PATH | grep -q -E "(^|:)\$item(\$|:)" ; then
        PATH="\$PATH:\$item"
    fi
}

add_path_after "/usr/local/bin"

EOF

########################################################################
##  Update VM with various scripts and tools

scrdir="$rfsdir/usr/local/bin"

mkdir -p $scrdir
cp $(which install-netronome-support-tools.sh) $scrdir
    check_status "failed to copy install script"

########################################################################

echo " - RSYNC files to VM"

rsync-vm.sh --vm-name "$VM_NAME" \
    -R $tmpdir/rfs/./ \
    --target /

    check_status "failed to transfer files to VM"

########################################################################
##  Packages to install on the VM

vmpkglist=()
vmpkglist+=( "git" "wget" "strace" "gawk" "unzip" "zip" "bc" )
vmpkglist+=( "expect" )
vmpkglist+=( "ntp" )
vmpkglist+=( "tmux" )
vmpkglist+=( "tcpdump" )
vmpkglist+=( "iperf3" )
vmpkglist+=( "ifupdown" )
vmpkglist+=( "pciutils" "python" ) # dpdk-devbind
vmpkglist+=( "socat" ) # dpdk-pktgen
vmpkglist+=( "vnstat" ) # Interface Rate Testing tool
vmpkglist+=( "hping3" ) # TCP-based ping
vmpkglist+=( "bwm-ng" ) # Bandwidth Monitoring Tool
vmpkglist+=( "fping" ) # Bandwidth Monitoring Tool

########################################################################
##  

scr="true"

scr="$scr && install-netronome-support-tools.sh"

scr="$scr && apt-get update"

scr="$scr && install-packages.sh --update ${vmpkglist[@]}"

scr="$scr && systemctl disable ntp"

scr="$scr && install-nfp-drv-kmods.sh"

scr="$scr && install-dpdk.sh $VM_BUILD_DPDK_VERSION"

########################################################################

scr="$scr && echo SUCCESS"

access-vm.sh --vm-name "$VM_NAME" "$scr"

    check_status "failed build base image"

########################################################################
rm -rf $tmpdir
########################################################################

echo "SUCCESS($0)"
exit 0
