#!/bin/bash

########################################################################
if [ "$1" == "--from-source" ]; then
    mode='source'
fi
########################################################################

# NUMA Socket to run virtio-forwarder on
: ${VIO_SOCKET:=0}

# Number of cores to skip
: ${VIO_CORE_SKIP:=1}

# Number of cores to use for virtio-forwarder
: ${VIO_CORE_COUNT:=2}

: ${VIO_GIT_REPO_URL:=https://github.com/Netronome/virtio-forwarder}

: ${VIO_GIT_BASE_DIR:=/opt/src}

: ${VIO_DPDK_VERSION:=17.11}

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
    if [ "$ID" == "ubuntu" ]; then
        if [ ${VERSION_ID%.*} -lt 18 ]; then
            mode='source'
        fi
    fi
    if [ "$mode" == "" ]; then
        case "$ID" in
          "ubuntu"|"debian") mode='ubuntu' ;;
          "centos"|"rhel"|"fedora") mode='fedora' ;;
        esac
    fi
fi
########################################################################

pkgs=()
pkgs+=( "git" )

case "$mode" in
  'ubuntu') # Repository Install
    pkgs+=( "add-apt-repository@ubuntu:software-properties-common" )
    ;;
  'fedora') # Repository Install
    pkgs+=( "semanage@fedora:policycoreutils-python" )
    pkgs+=( "yum-plugin-copr" )
    ;;
  'source')
    sphinx_file="/usr/lib/python2.7/dist-packages/sphinx/__main__.py"
    pkgs+=( "$sphinx_file@ubuntu:python-sphinx" )
    pkgs+=( "/usr/share/doc/python-zmq@python-zmq" )
    ;;
  *)
    false ; check_status "unsupported system"
esac

install-packages.sh ${pkgs[@]} \
    || exit -1

########################################################################

case "$mode" in
  'ubuntu')
    add-apt-repository -y ppa:netronome/virtio-forwarder
        check_status "failed to add repository 'ppa:netronome/virtio-forwarder'"
    apt-get update
        check_status "failed to 'apt-get update'"
    apt-get install -y virtio-forwarder
        check_status "failed to install virtio-forwarder"
    ;;
  'fedora')
    yum copr enable -y netronome/virtio-forwarder
        check_status "failed to enable Netronome repository"
    yum install -y virtio-forwarder
        check_status "failed to install virtio-forwarder"
    ;;
  'source')
    # First, install DPDK
    install-dpdk.sh $VIO_DPDK_VERSION \
        || exit -1
    # The installation above should leave all settings in:
    . /etc/dpdk-$VIO_DPDK_VERSION.conf

    mkdir -p $VIO_GIT_BASE_DIR
    if [ -d $VIO_GIT_BASE_DIR/virtio-forwarder ]; then
        {   cd $VIO_GIT_BASE_DIR/virtio-forwarder
            git pull
                check_status "failed to update (pull) git repository"
        }
    else
        {   cd $VIO_GIT_BASE_DIR
            git clone $VIO_GIT_REPO_URL
                check_status "failed to clone $VIO_GIT_REPO_URL"
        }
    fi
    make -C $VIO_GIT_BASE_DIR/virtio-forwarder
        check_status "failed to build virtio-forwarder"
    make -C $VIO_GIT_BASE_DIR/virtio-forwarder install
        check_status "failed to install virtio-forwarder"
    ;;
esac
    
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
