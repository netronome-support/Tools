#!/bin/bash

########################################################################
# This script is maintained at:
#   https://github.com/netronome-support/Tools
########################################################################
##  Local Configuration

l_cfg_list=()
l_cfg_list+=( "/etc/local/build-base-vm.cfg" )
l_cfg_list+=( "$HOME/.config/build-base-vm.cfg" )
l_cfg_list+=( "$LOCAL_BUILD_BASE_VM_CFG_FILE" )
for fname in ${l_cfg_list[@]} ; do
    if [ -f $fname ]; then
        . $fname
    fi
done

########################################################################
##  Variable Defaults:

VM_NAME="$BUILD_VM_NAME"

########################################################################

: "${VM_BUILD_DPDK_VERSION:=19.02}"
: "${VM_BUILD_DPDK_PKTGEN_VERSION:=3.5.0}"

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
##  Setup Root File System (for upload to VM)

rfsdir="$tmpdir/rfs"
mkdir -p $rfsdir
mkdir -p $rfsdir/etc/profile.d

########################################################################
scrdir="$rfsdir/usr/local/bin"
mkdir -p $scrdir
########################################################################
mkdir -p $rfsdir/root
touch $rfsdir/root/.hushlogin
########################################################################
##  

: ${LOCAL_FIND_HTTP_PROXY_TOOL:="get-server-proxy-settings.sh"}
if which $LOCAL_FIND_HTTP_PROXY_TOOL > /dev/null 2>&1 ; then
    SERVER_HTTP_PROXY=$($LOCAL_FIND_HTTP_PROXY_TOOL)
fi

if [ "$SERVER_HTTP_PROXY" != "" ]; then
cat <<EOF > $tmpdir/ns-proxy.sh

# Netronome Script enabling proxy

export http_proxy=$IVG_HTTP_PROXY

EOF
fi

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
##  Copy scripts to Base VM

vm_scr_list+=( "install-netronome-support-tools.sh" )
vm_scr_list+=( "install-packages.sh" )

for vm_scr_name in "${vm_scr_list[@]}" ; do
    if [ -f "$vm_scr_name" ]; then
        cp -a "$vm_scr_name" $scrdir
        continue
    fi
    file="$(which $vm_scr_name 2> /dev/null)"
    if [ -f $file ]; then
        cp -a "$file" $scrdir
    fi
done

########################################################################
##  Upload package files to VM

if [ -d "$VM_BUILD_UPLOAD_FS_ROOT" ]; then
    rsync -a -R $VM_BUILD_UPLOAD_FS_ROOT/./ $rfsdir/./
        check_status "local rsync failed - check for space"
fi

########################################################################
##  Upload package files to VM

dldir="$rfsdir/var/cache/download"

slist=()
slist+=( "/var/cache/download" )
slist+=( "$HOME" )
slist+=( "$LOCAL_VM_PKGS_DIR" )

flist=()
flist+=( "dpdk-$VM_BUILD_DPDK_VERSION.tar.xz" )
flist+=( "pktgen-$VM_BUILD_DPDK_PKTGEN_VERSION.tar.gz" )
flist+=( $VM_BUILD_UPLOAD_PKGS_LIST )
for fn in ${flist[@]} ; do
    if [ -f $fn ]; then
        mkdir -p $dldir
        cp $fn $dldir \
            || exit -1
        continue
    fi
    for sn in ${slist[@]} ; do
        if [ -f $sn/$fn ]; then
            mkdir -p $dldir
            cp $sn/$fn $dldir \
                || exit -1
            break
        fi
    done
done

########################################################################
echo " - RSYNC files to VM"

rsync-vm.sh --vm-name "$VM_NAME" \
    -R $tmpdir/rfs/./ \
    --target /

    check_status "failed to transfer files to VM"

########################################################################
echo " - run setup script on VM"

scr="true"

scr="$scr && install-netronome-support-tools.sh"

scr="$scr && setup-base-vm-tools.sh"

if [ "$BASE_IMAGE_OS" == "centos" ]; then
    scr="$scr && setup-centos-base-vm.sh"
fi

scr="$scr && echo SUCCESS"

access-vm.sh --vm-name "$VM_NAME" "$scr"

    check_status "failed build base image"

########################################################################
rm -rf $tmpdir
########################################################################

echo "SUCCESS($0)"
exit 0
