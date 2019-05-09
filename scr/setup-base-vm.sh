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
echo " - run setup script on VM"

scr="true"

scr="$scr && install-netronome-support-tools.sh"

scr="$scr && setup-base-vm-tools.sh"

scr="$scr && echo SUCCESS"

access-vm.sh --vm-name "$VM_NAME" "$scr"

    check_status "failed build base image"

########################################################################
rm -rf $tmpdir
########################################################################

echo "SUCCESS($0)"
exit 0
