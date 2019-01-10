#!/bin/bash

########################################################################

# Log File Location
: "${NS_INSTALL_LOG_DIR:=/var/log/install}"

# URL of NFP Driver Git Repository
: "${NS_GIT_NFP_DRV_REPO_URL:=https://github.com/Netronome/nfp-drv-kmods}"

########################################################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}

########################################################################

if ! which install-packages.sh > /dev/null 2>&1 ; then
    scrname="install-packages.sh"
    url="https://raw.githubusercontent.com/netronome-support"
    url="$url/Tools/master/scr/$scrname"
    echo " - Download $url and place in /usr/local/bin"
    wget --quiet $url -O /usr/local/bin/$scrname
        check_status "failed to download $url"
    chmod a+x /usr/local/bin/$scrname
        check_status "failed to make /usr/local/bin/$scrname executable"
fi

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

install-packages.sh ${pkgs[@]} \
    || exit -1

########################################################################
logdir=$NS_INSTALL_LOG_DIR
mkdir -p $logdir

########################################################################

drvdir="/opt/git/nfp-drv-kmods"
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
    | tee $logdir/make-nfp-drv-kmods.log \
    || exit -1

########################################################################

if [ "$SKIP_INSTALL" != "" ]; then
    exit 0
fi

make -C $drvdir install \
    | tee $logdir/make-install-nfp-drv-kmods.log \
    || exit -1

########################################################################

ko_file="$drvdir/src/nfp.ko"

if [ ! -f $ko_file ]; then
    echo "ERROR: NFP driver missing at $ko_file"
    exit -1
fi

########################################################################

mkdir -p /etc/NetworkManager/conf.d
cat <<EOF > /etc/NetworkManager/conf.d/nfp.conf
# Added by $0 on $(date)
[keyfile]
unmanaged-devices=driver:nfp,driver:nfp_netvf
EOF

cat <<EOF > /etc/modprobe.d/nfp-drv-location.conf
install nfp insmod $drvdir/src/nfp.ko
EOF

depmod --all

########################################################################
echo "SUCCESS($(basename $0))"
exit 0
