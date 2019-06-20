#!/bin/bash

########################################################################
# This script is maintained at:
#   https://github.com/netronome-support/Tools
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
: "${CENTOS_BUILD_INDEX:=1811}"
: "${CENTOS_VERSION:=7}"
: "${CENTOS_ARCH:=x86_64}"

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
: "${UBUNTU_VERSION:=bionic}"

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
    ;;
  "ubuntu")
    : "${IMAGE_URL:=$UBUNTU_URL}"
    : "${IMAGE_FILE:=$UBUNTU_IMAGE_FILE}"
    : "${IMAGE_NAME:=Ubuntu-${UBUNTU_VERSION}-base}"
    OS_PKG_TOOL="apt-get"
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
# SSH Authorization Key File
: "${SSH_PUB_KEY_FILE:=$HOME/.ssh/id_rsa.pub}"

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
pkgs+=( "cloud-localds@ubuntu:cloud-image-utils,rhel:cloud-utils" )
pkgs+=( "genisoimage@rhel:genisoimage" )
pkgs+=( "qemu-system-x86_64@qemu-system-x86" )
pkgs+=( "virt-install@ubuntu:virtinst,rhel:virt-install" )

if [ "$ID-$VERSION_ID" == "ubuntu-18.10" ]; then
    pkgs+=( "/usr/share/doc/libvirt-daemon-system/copyright@libvirt-daemon-system" )
else
    pkgs+=( "/usr/share/doc/libvirt-bin/copyright@libvirt-bin" )
fi

install-packages.sh --cache-update ${pkgs[@]}
    check_status "failed to install pre-requisite packages"

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

if [ "$SSH_PUB_KEY_STR" == "none" ]; then
    SSH_PUB_KEY_STR=""
elif [ "$SSH_PUB_KEY_STR" == "" ]; then
    if [ ! -f "$SSH_PUB_KEY_FILE" ]; then
        echo " - Create SSH Key"
        run ssh-keygen -t rsa -f ${SSH_PUB_KEY_FILE/.pub} -q -P ""
        test -f ${SSH_PUB_KEY_FILE}
            check_status "SSH public key file ($SSH_PUB_KEY_FILE) was not created"
    fi
    SSH_PUB_KEY_STR=$(cat $SSH_PUB_KEY_FILE)
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
if [ "$SSH_PUB_KEY_STR" != "" ]; then
    ( echo "ssh_authorized_keys:" ; \
      echo "    - $SSH_PUB_KEY_STR" \
    ) >> $cloud_data_text_file
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
