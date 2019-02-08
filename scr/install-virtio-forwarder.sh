#!/bin/bash

########################################################################

# NUMA Socket to run virtio-forwarder on
: ${VIO_SOCKET:=0}

# Number of cores to skip
: ${VIO_CORE_SKIP:=1}

# Number of cores to use for virtio-forwarder
: ${VIO_CORE_COUNT:=2}

########################################################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}

########################################################################
##  Stop virtio-forwarder if 'active'

systemctl is-active virtio-forwarder > /dev/null
if [ $? -eq 0 ]; then
    systemctl stop virtio-forwarder
fi

########################################################################
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" == "ubuntu" ] && [ ${VERSION_ID%.*} -lt 18 ]; then
        echo "ERROR: preperably only use Ubuntu 18.04 or later"
        echo " - the DPDK version might be too old"
        exit -1
    fi
fi
########################################################################

pkgs=()
pkgs+=( "add-apt-repository@ubuntu:software-properties-common" )
# RHEL & CentOS:
pkgs+=( "semanage@fedora:policycoreutils-python" )

install-packages.sh ${pkgs[@]} \
    || exit -1

########################################################################

add-apt-repository -y ppa:netronome/virtio-forwarder
    check_status "failed to add repository 'ppa:netronome/virtio-forwarder'"
apt-get update
    check_status "failed to 'apt-get update'"
apt-get install -y virtio-forwarder
    check_status "failed to install virtio-forwarder"

########################################################################

cpuset=$(list-socket-vcpus.sh \
    --socket $VIO_SOCKET \
    --skip $VIO_CORE_SKIP \
    --count $VIO_CORE_COUNT \
    --delim ',' \
    )

########################################################################

function set_vio_opt () {
    local name="$1"
    local value="$2"
    local cfgfile="/etc/default/virtioforwarder"
    sed -r "s/^\s*($name)=.*\$/\1=$value/" \
        -i $cfgfile
        check_status "failed to update $cfgfile"
}

########################################################################

set_vio_opt "VIRTIOFWD_CPU_MASK" "$cpuset"
set_vio_opt "VIRTIOFWD_VHOST_CLIENT" ""

# Leave this high until everything is working
set_vio_opt "VIRTIOFWD_LOG_LEVEL" "7"

########################################################################

setup-hugepages.sh --page-size 2MB --min-pages 1375
    check_status "failed to setup hugepages"

########################################################################
##  Enable Hugepage access via apparmor

huge_mnt_list=$(mount \
    | sed -rn 's/^hugetlbfs\son\s(\S+)\s.*$/\1/p' )
libvirt_list=()
for mntpnt in $huge_mnt_list ; do
    if [ -d $mntpnt/libvirt/qemu ]; then
        libvirt_list+=( $mntpnt )
    fi
done

# Under construction ...

########################################################################

# Enable to START after boot-up:
systemctl enable virtio-forwarder
    check_status "failed to enable virtio-forwarder"

# Start it now:
systemctl start virtio-forwarder
    check_status "failed to start virtio-forwarder"

########################################################################
# Notice that the virtio-forwarder will need to be restarted in order to
# access ports that are currently not configured with the vfio-pci driver.
########################################################################
echo "SUCCESS($(basename $0))"
exit 0
