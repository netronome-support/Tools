#!/bin/bash

########################################################################
##  Defaults:

# URL of NFP Driver Git Repository
: "${NS_GIT_NFP_DRV_REPO_URL:=https://github.com/Netronome/nfp-drv-kmods}"

if [ "$(whoami)" == "root" ]; then
    # Installation Directory
    : ${GIT_REPO_BASE_DIR:="/opt/src/netronome-support"}

    # Log File Location
    : "${NS_INSTALL_LOG_DIR:=/var/log/install}"

    # No need for 'sudo'
    SUDO=""
else
    : ${GIT_REPO_BASE_DIR:="$HOME/build/git/netronome"}
    : "${NS_INSTALL_LOG_DIR:=$HOME/.logs}"
    : ${DPDK_INSTALL_DIR:="$HOME/build"}
    : ${DPDK_DOWNLOAD_DIR:="$HOME/.cache/download"}
    : ${DPDK_SETTINGS_DIR:="$HOME/.config/dpdk"}
    SUDO="sudo"
fi

########################################################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}

########################################################################

which install-packages.sh > /dev/null 2>&1
    check_status "missing 'install-packages.sh"

# To install:
#   git clone https://github.com/netronome-support/Tools
#   sudo ./Tools/install.sh

########################################################################

pkgs=()
pkgs+=( "git@" "make@" "gcc@" )
#pkgs+=( "build-essential" )

# Kernel Header Files:
pkgs+=( "/usr/src/kernels/$(uname -r)/include@centos:kernel-devel" )
pkgs+=( "/usr/src/linux-headers-$(uname -r)/include@ubuntu:linux-headers-$(uname -r)" )

# The following is needed for 'Signing Kernel module'
pkgs+=( "openssl@" "perl@" "mokutil@" )
pkgs+=( "keyctl@keyutils" )

install-packages.sh ${pkgs[@]}
    check_status "failed to install pre-requisite packages"

########################################################################
logdir=$NS_INSTALL_LOG_DIR
mkdir -p $logdir
    check_status "failed to create '$logdir'"

########################################################################

drvdir="$GIT_REPO_BASE_DIR/nfp-drv-kmods"
if [ ! -d $drvdir ]; then
    echo " - Clone $NS_GIT_NFP_DRV_REPO_URL"
    git clone $NS_GIT_NFP_DRV_REPO_URL $drvdir
        check_status "failed to clone $NS_GIT_NFP_DRV_REPO_URL"
fi

########################################################################

# The following is needed or the 'make install' will spit out:
# - SSL error:02001002:system library:fopen:No such file or directory: bss_file.c:175
# - SSL error:2006D080:BIO routines:BIO_new_file:no such file: bss_file.c:178

if [ ! -f $HOME/.ssh/id_rsa ]; then
    ssh-keygen -q -t rsa -N "" < /dev/zero > /dev/null 2>&1
fi

# Needed for the 'SSL error' above:
mokutil --disable-validation

########################################################################

make -C $drvdir \
    | tee $logdir/make-nfp-drv-kmods.log
    check_status "failed to compile NFP Driver kmods"

########################################################################

if [ "$SKIP_INSTALL" != "" ]; then
    exit 0
fi

$SUDO make -C $drvdir install 2>&1 \
    | tee $logdir/make-install-nfp-drv-kmods.log \
    | grep -v "SSL error" \
    | grep -vE "^sign-file"
    check_status "failed to install NFP Driver kmods"

########################################################################

ko_file="$drvdir/src/nfp.ko"

test -f $ko_file
    check_status "NFP driver missing at $ko_file"

########################################################################

tmpdir=$(mktemp --directory)

nm_cfg_dir="/etc/NetworkManager/conf.d"

$SUDO mkdir -p $nm_cfg_dir
    check_status "failed to create $nm_cfg_dir"

$SUDO cat <<EOF > $tmpdir/nfp.conf
# Added by $0 on $(date)
[keyfile]
unmanaged-devices=driver:nfp,driver:nfp_netvf
EOF

$SUDO cat <<EOF > $tmpdir/nfp-drv-location.conf
install nfp insmod $drvdir/src/nfp.ko
EOF

$SUDO cp -f $tmpdir/nfp.conf $nm_cfg_dir
$SUDO cp -f $tmpdir/nfp-drv-location.conf /etc/modprobe.d

$SUDO depmod --all

rm -rf $tmpdir

########################################################################
echo "SUCCESS($(basename $0))"
exit 0
