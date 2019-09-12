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

# Location for downloading files (while actively downloading)
: "${DOWNLOAD_CACHE_DIR:=/var/cache/download/pending}"

# Location for downloaded cloud image (before being modified)
: "${CLOUD_IMAGES_DIR:=/opt/download/cloud-images}"

# Location for the resulting base image
: "${BASE_IMAGES_DIR:=/var/lib/libvirt/images}"

# Location for Cloud-Image User data
: "${CLOUD_IMAGE_USER_DATA_DIR:=/var/lib/libvirt/images/user-data}"

# VM Config Information
: "${BASE_VM_META_FILE:=/etc/base-vm.cfg}"

# Log Directory
: "${logdir:=/var/log/build-base-vm}"

########################################################################
##  Variable Defaults:

# Base Image FS Size
: "${BASE_IMAGE_FS_SIZE:=30G}"

# Script for setting up VM image
: "${BASE_VM_SETUP_SCRIPT:=/usr/local/bin/setup-base-vm.sh}"

########################################################################
##  CentOS

# CentOS 7 Build Number
: ${CENTOS_BUILD_INDEX:=1811}
: ${CENTOS_VERSION:=7}
: ${CENTOS_ARCH:=x86_64}
: ${CENTOS_OS_VARIANT:='centos7.0'}

# URL for CentOS Cloud Images
: "${CENTOS_URL:=https://cloud.centos.org/centos/$CENTOS_VERSION/images}"

# Default File Name
dfname="CentOS-$CENTOS_VERSION-$CENTOS_ARCH"
dfname="$dfname-GenericCloud-${CENTOS_BUILD_INDEX}.qcow2"

# CentOS Cloud Image File
: "${CENTOS_IMAGE_FILE:=$dfname}"

########################################################################
##  Ubuntu 

# xenial = 16.04, artful = 17.10, bionic = 18.04
: ${UBUNTU_VERSION:=bionic}
: ${UBUNTU_OS_VARIANT:='ubuntu18.04'}

# URL for Ubuntu Cloud Images
: "${UBUNTU_URL:=https://cloud-images.ubuntu.com/${UBUNTU_VERSION}/current}"

case "$UBUNTU_VERSION" in
  "xenial")
    : ${UBUNTU_IMAGE_FILE_TAIL:=server-cloudimg-amd64-disk1.img} ;;
  *)
    : ${UBUNTU_IMAGE_FILE_TAIL:=server-cloudimg-amd64.img} ;;
esac

# Ubuntu Cloud Image File
: "${UBUNTU_IMAGE_FILE:=${UBUNTU_VERSION}-$UBUNTU_IMAGE_FILE_TAIL}"

########################################################################
##  Selection

: "${BASE_IMAGE_OS:=ubuntu}"

case "$BASE_IMAGE_OS" in
  "centos")
    : "${IMAGE_URL:=$CENTOS_URL}"
    : "${IMAGE_FILE:=$CENTOS_IMAGE_FILE}"
    : "${IMAGE_NAME:=CentOS-${CENTOS_VERSION}-${CENTOS_BUILD_INDEX}-base}"
    OS_PKG_TOOL="yum"
    : ${OS_VARIANT:=$CENTOS_OS_VARIANT}
    ;;
  "ubuntu")
    : "${IMAGE_URL:=$UBUNTU_URL}"
    : "${IMAGE_FILE:=$UBUNTU_IMAGE_FILE}"
    : "${IMAGE_NAME:=Ubuntu-${UBUNTU_VERSION}-base}"
    OS_PKG_TOOL="apt-get"
    : ${OS_VARIANT:=$UBUNTU_OS_VARIANT}
    ;;
  *)
    echo "ERROR: unknown OS ($BASE_IMAGE_OS)"
    exit -1
esac

: "${IMAGE_PLAIN_FILE_NAME:=${IMAGE_NAME}-$(date +'%Y-%m-%d').qcow2}"
: "${IMAGE_CLOUD_FILE_NAME:=${IMAGE_NAME}-$(date +'%Y-%m-%d')-cloud-image.qcow2}"
: "${RESULT_PLAIN_IMAGE_FILE:=${BASE_IMAGES_DIR}/${IMAGE_PLAIN_FILE_NAME}}"
: "${RESULT_CLOUD_IMAGE_FILE:=${BASE_IMAGES_DIR}/${IMAGE_CLOUD_FILE_NAME}}"

########################################################################
# Standard SSH Key File
: "${SSH_KEY_FILE:=$HOME/.ssh/id_rsa}"

# Extra VM Access Key File
: "${SSH_VM_ACCESS_KEY_FILE:=$HOME/.ssh/vm-access-key}"

# VM Root User Password
: "${VM_ROOT_PASSWORD:=password}"

# Name of VM while preparing
: "${VM_NAME:=pending-$IMAGE_NAME}"

########################################################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($0): $errmsg"
        exit -1
    fi
}

function run () {
    local cmdlog="$logdir/cmd-$1-output.log"
    printf "# %s\n%s\n" \
        "$(date)" "$*" \
        | tee -a $logfile \
        >> $cmdlog
    "$@" 2>&1 > $cmdlog
    if [ $? -ne 0 ]; then
        echo "ERROR ..."
        cat $cmdlog
        exit -1
    fi
}

# Any command in a pipeline must trigger an error:
set -o pipefail

########################################################################
test "$(whoami)" == "root"
    check_status "must be run as 'root'"
########################################################################
which wget > /dev/null 2>&1
    check_status "missing 'wget' tool"
which install-netronome-support-tools.sh > /dev/null 2>&1
if [ $? -ne 0 ]; then
    url="https://raw.githubusercontent.com/netronome-support/Tools"
    url="$url/master/scr/install-netronome-support-tools.sh"
    wget --quiet "$url" -O /usr/local/bin
        check_status "failed to download $url"
fi

install-netronome-support-tools.sh
    check_status "failed to run 'install-netronome-support-tools.sh'"

########################################################################
test -x $BASE_VM_SETUP_SCRIPT
    check_status "missing script at '$BASE_VM_SETUP_SCRIPT' for VM Setup"
########################################################################
##  Required sub-scripts
reqscrlist=()
reqscrlist+=( "virsh-await-state.sh" )
reqscrlist+=( "virsh-await-access.sh" )
reqscrlist+=( "virsh-get-vm-ipaddr.sh" )
reqscrlist+=( "install-packages.sh" )
reqscrlist+=( "rsync-vm.sh" )
reqscrlist+=( "access-vm.sh" )
for reqscr in "${reqscrlist[@]}" ; do
    which $reqscr > /dev/null 2>&1
        check_status "missing script $reqscr"
done
########################################################################
sshopts+=()
sshopts+=( "-q" )
sshopts+=( "-o" "StrictHostKeyChecking=no" )
sshopts+=( "-o" "UserKnownHostsFile=/dev/null" )
sshopts+=( "-o" "ConnectionAttempts=30" )
sshopts+=( "-o" "ServerAliveInterval=300" )
########################################################################
mkdir -p $logdir
    check_status "failed to create log directory '$logdir'"
logfile="$logdir/build-base-vm-$(date +'%y-%m-%d')-${IMAGE_NAME}.log"
########################################################################
cat <<EOF > $logfile
--------------------
Start $(date)
OS: $BASE_IMAGE_OS
URL: $IMAGE_URL
NAME: $IMAGE_NAME
FILE: $IMAGE_FILE
--------------------
EOF

########################################################################
test -f /etc/os-release
    check_status "missing /etc/os-release"
. /etc/os-release
########################################################################
## Install pre-requisite packages

pkgs=()
pkgs+=( "wget@" )
pkgs+=( "gawk@" )
pkgs+=( "ssh-keygen@openssh-client" )
pkgs+=( "qemu-system-x86_64@qemu-system-x86" )

case "$ID" in
  "ubuntu")
    if [ "$VERSION_ID" == "18.10" ]; then
        pkgs+=( "libvirt-daemon-system" )
    else
        pkgs+=( "libvirt-bin" )
    fi
    pkgs+=( "cloud-image-utils" )
    pkgs+=( "virtinst" )
    ;;
  "centos"|"rhel"|"fedora")
    pkgs+=( "libvirt" "libvirt-python" )
    pkgs+=( "cloud-init" "cloud-utils" )
    pkgs+=( "genisoimage" )
    pkgs+=( "libguestfs-tools" )
    pkgs+=( "virt-install" )
    ;;
esac

install-packages.sh --cache-update ${pkgs[@]}
    check_status "failed to install pre-requisite packages"

########################################################################
case "$ID" in
  "centos"|"rhel"|"fedora")
    systemctl enable libvirtd
        check_status "failed to enable libvirtd"
    systemctl start libvirtd
        check_status "failed to start libvirtd"
    ;;
esac
########################################################################
##  Look for local copy of Cloud Image

if [ "$BASE_IMAGE_FILE" != "" ]; then
    if [ ! -f "$BASE_IMAGE_FILE" ]; then
        echo "ERROR: missing base image file $BASE_IMAGE_FILE"
        exit -1
    fi
elif [ "$IMAGE_REBUILD" != "" ]; then
    if [ ! -f /etc/base-vm.cfg ]; then
        echo "ERROR($(basename $0)): no previous build"
        exit -1
    fi
    BASE_IMAGE_FILE=$(cat /etc/base-vm.cfg \
        | sed -rn 's/^BASE_PLAIN_IMAGE_FILE=(\S+)$/\1/p')
    if [ "$BASE_IMAGE_FILE" == "" ] || [ ! -f "$BASE_IMAGE_FILE" ]; then
        echo "ERROR($(basename $0)): missing image from previous build"
        exit -1
    fi
else
    sp=()
    sp+=( "$CLOUD_IMAGES_DIR" )
    sp+=( "$HOME" )
    sp+=( "$LOCAL_BASE_CLOUD_IMAGE_DIR" )
    sp+=( "/var/lib/libvirt/images" )

    for sd in ${sp[@]} ; do
        if [ -f "$sd/$IMAGE_FILE" ]; then
            BASE_IMAGE_FILE="$sd/$IMAGE_FILE"
            break
        fi
    done
fi

########################################################################
##  Download Cloud Image

if [ "$BASE_IMAGE_FILE" == "" ] || [ ! -f "$BASE_IMAGE_FILE" ]; then
    echo " - Download $IMAGE_FILE"

    BASE_IMAGE_FILE="$CLOUD_IMAGES_DIR/$IMAGE_FILE"

    run mkdir -p $DOWNLOAD_CACHE_DIR
    run mkdir -p $CLOUD_IMAGES_DIR

    # Store the file under a different name while being downloaded
    tmpfile="$DOWNLOAD_CACHE_DIR/$IMAGE_FILE"
    url="$IMAGE_URL/$IMAGE_FILE"

    wget --quiet --continue "$url" -O $tmpfile

        check_status "failed to download $url"

    run mv -f $tmpfile $BASE_IMAGE_FILE
fi

########################################################################

printf " - Using base image:\n   %s\n" "$BASE_IMAGE_FILE" \
    | tee -a $logfile

########################################################################
##  SSH - For VM authentication, we need a key

pub_ssh_key_list=()

if [ "$SSH_PUB_KEY_STR" != "none" ]; then

    # One public key may be passed via a variable
    if [ "$SSH_PUB_KEY_STR" != "" ]; then
        pub_ssh_key_list+=( "$SSH_PUB_KEY_STR" )
    fi

    if [ "$SSH_KEY_FILE" != "none" ]; then
        if [ ! -f $SSH_KEY_FILE ]; then
            run ssh-keygen -t rsa -f "$SSH_KEY_FILE" -q -P ""
        fi
        pubfile="${SSH_KEY_FILE}.pub"
        test -f $pubfile
            check_status "missing the public key file $pubfile"
        pub_ssh_key_list+=( "$(cat $pubfile)" )
    fi

    # Besides the host's SSH key, we create an extra key that can
    # be shared with multiple hosts for VM access.
    if [ "$SSH_VM_ACCESS_KEY_FILE" != "none" ]; then
        if [ ! -f $SSH_VM_ACCESS_KEY_FILE ]; then
            run ssh-keygen -t rsa -f "$SSH_VM_ACCESS_KEY_FILE" \
                -q -P "" -C "vm-access-key"
        fi
        pubfile="${SSH_VM_ACCESS_KEY_FILE}.pub"
        test -f $pubfile
            check_status "missing the public key file $pubfile"
        pub_ssh_key_list+=( "$(cat $pubfile)" )
    fi

    # Allow for additinal public key files to be included
    for pubfile in $SSH_PUB_KEY_FILE_LIST ; do
        if [ -f $pubfile ]; then
            pub_ssh_key_list+=( "$(cat $pubfile)" )
        fi
    done
fi        

########################################################################
##  Preparing Cloud Image configuration file

run mkdir -p $CLOUD_IMAGE_USER_DATA_DIR

cd_fname="cloud-image-user-data-$(date +'%Y-%m-%d-%H%M%S')"
cloud_data_text_file="$CLOUD_IMAGE_USER_DATA_DIR/${cd_fname}.txt"
cloud_data_img_file="$CLOUD_IMAGE_USER_DATA_DIR/${cd_fname}.img"

cat > $cloud_data_text_file << EOF
#cloud-config
debug: True
ssh_pwauth: True
disable_root: false
EOF

## Specify SSH Authorized Key
if [ ${#pub_ssh_key_list[@]} -gt 0 ]; then
    echo "ssh_authorized_keys:" >> $cloud_data_text_file
    for pub_key_str in "${pub_ssh_key_list[@]}" ; do
        echo "    - $pub_key_str" >> $cloud_data_text_file
    done
fi

## Specify Password
cat >> $cloud_data_text_file << EOF
chpasswd:
  list: |
    root:$VM_ROOT_PASSWORD
  expire: false
EOF

########################################################################
cmdlist=()
cmdlist+=( "mkdir -m 700 -p /root/.ssh" )
# CentOS
##  cmdlist+=( "cp /home/centos/.ssh/authorized_keys /root/.ssh" )
cmdlist+=( "sed -r 's/^[#\s]*(PermitRootLogin)\s.*$/\1 yes/' -i /etc/ssh/sshd_config" )
# Uninstall cloud-init for now, and re-install it at the end
cmdlist+=( "$OS_PKG_TOOL remove -y cloud-init" )
cmdlist+=( "poweroff" )

cat >> $cloud_data_text_file << EOF
write_files:
  - path: /root/README 
    content: "Netronome Performance VM"
EOF

echo "runcmd:" >> $cloud_data_text_file
for cmd in "${cmdlist[@]}" ; do
    echo "- $cmd" >> $cloud_data_text_file
done

########################################################################
##  

run cloud-localds $cloud_data_img_file $cloud_data_text_file

########################################################################
##  Blindly Destroy and Undefine existing VM (if one exists)

virsh destroy "$VM_NAME" > /dev/null 2>&1
virsh undefine "$VM_NAME" > /dev/null 2>&1

########################################################################
##  Create VM Base Image

BUILD_IMAGE_FILE="$BASE_IMAGES_DIR/pending-$(basename $BASE_IMAGE_FILE)"

# Delete existing Base Image file
if [ -f $BUILD_IMAGE_FILE ]; then
    rm -f $BUILD_IMAGE_FILE
fi

# Create a copy of the downloaded Base Cloud Image file
run cp -f $BASE_IMAGE_FILE $BUILD_IMAGE_FILE

########################################################################

run qemu-img resize $BUILD_IMAGE_FILE $BASE_IMAGE_FS_SIZE

########################################################################
##  

cpu_model=$(virsh capabilities \
    | grep -o '<model>.*</model>' \
    | head -1 \
    | sed 's/\(<model>\|<\/model>\)//g')

echo " - Create new VM"

opts=()
opts+=( "--name" "$VM_NAME" )
opts+=( "--disk" "path=$BUILD_IMAGE_FILE,format=qcow2,bus=virtio,cache=none" )
if [ "$IMAGE_REBUILD" == "" ]; then
    opts+=( "--disk" "$cloud_data_img_file,device=cdrom" )
fi
opts+=( "--ram" "4012" )
opts+=( "--vcpus" "$(nproc)" )
opts+=( "--cpu" "$cpu_model" )
opts+=( "--network" "bridge=virbr0,model=virtio" )
opts+=( "--graphics" "vnc" )
opts+=( "--accelerate" )
opts+=( "--os-type=linux" )
opts+=( "--os-variant" "$OS_VARIANT" )
opts+=( "--noautoconsole" )
opts+=( "--import" )

run virt-install ${opts[@]}

########################################################################

if [ "$IMAGE_REBUILD" == "" ]; then

    virsh-await-state.sh --state 'shut off' --timeout 180 "$VM_NAME"
        check_status "VM '$VM_NAME' did not shutdown"

    ##  De-attach (eject) cloud data image
    run virsh change-media $VM_NAME $cloud_data_img_file --eject --config

    run rm -f $cloud_data_img_file

    ##  Re-start the VM

    run virsh start $VM_NAME

fi

########################################################################

virsh-await-state.sh --state 'running' "$VM_NAME"
    check_status "VM '$VM_NAME' was not successfully started"

virsh-await-access.sh "$VM_NAME"
    check_status "VM '$VM_NAME' did not boot up"

########################################################################
##  Save Settings

cat <<EOF | tee -a $logfile > $BASE_VM_META_FILE
# Created on $(date)
BASE_IMAGE_OS=$BASE_IMAGE_OS
BASE_IMAGE_NAME=$IMAGE_NAME
BUILD_VM_NAME=$VM_NAME
BUILD_IMAGE_FILE=$BUILD_IMAGE_FILE
OS_PKG_TOOL=$OS_PKG_TOOL
BASE_VM_SETUP_SCRIPT=$BASE_VM_SETUP_SCRIPT
# Result Image File
BASE_PLAIN_IMAGE_FILE=$RESULT_PLAIN_IMAGE_FILE
BASE_CLOUD_IMAGE_FILE=$RESULT_CLOUD_IMAGE_FILE

EOF

########################################################################
##  Update VM with various scripts and tools

export logdir
export logfile
export BUILD_VM_NAME="$VM_NAME"
export BASE_IMAGE_OS

$BASE_VM_SETUP_SCRIPT \
    | tee -a $logfile

    check_status "failed to setup VM"

########################################################################

run virsh shutdown "$VM_NAME"

virsh-await-state.sh --state 'shut off' "$VM_NAME"
    check_status "VM '$VM_NAME' did not shutdown"

run cp -f $BUILD_IMAGE_FILE $RESULT_PLAIN_IMAGE_FILE

########################################################################
##  Re-start the VM

run virsh start $VM_NAME

virsh-await-state.sh --state 'running' "$VM_NAME"
    check_status "VM '$VM_NAME' was not successfully started"

virsh-await-access.sh "$VM_NAME"
    check_status "VM '$VM_NAME' did not boot up"

########################################################################
##  Re-install cloud-init package

scr="true"
if [ "$OS_PKG_TOOL" == "apt" ] || [ "$OS_PKG_TOOL" == "apt-get" ]; then
    scr="$scr && $OS_PKG_TOOL update"
fi
scr="$scr && $OS_PKG_TOOL install -y cloud-init"
scr="$scr && echo SUCCESS"

access-vm.sh --vm-name "$VM_NAME" "$scr" \
    | tee -a $logfile

    check_status "failed build base image"

########################################################################
##  

run virsh shutdown "$VM_NAME"

virsh-await-state.sh --state 'shut off' "$VM_NAME"
    check_status "VM '$VM_NAME' did not shutdown"

run cp -f $BUILD_IMAGE_FILE $RESULT_CLOUD_IMAGE_FILE

########################################################################
cat <<EOF >> $logfile
--------------------
Finish $(date)
--------------------
EOF
########################################################################

echo
echo "Image (plain): $RESULT_PLAIN_IMAGE_FILE"
echo "Image (cloud): $RESULT_CLOUD_IMAGE_FILE"
echo
echo "SUCCESS($0)"
exit 0
