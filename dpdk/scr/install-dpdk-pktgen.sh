#!/bin/bash

if [ -f "$1" ]; then
    pkgfile="$1"
elif [ -d "$1" ]; then
    pkgdir="$1"
elif [ "$1" != "" ]; then
    version="$1"
else
    echo "Usage: <pktgen package file>|<pktgen version>"
    exit -1
fi

########################################

pkgname="pktgen"

# Installation Directory
srcdir="/opt/src"

########################################

if [ ! -f /etc/dpdk.conf ]; then
    echo "ERROR: DPDK settings expected in /etc/dpdk.conf"
    echo " - use install-dpdk.sh <version> to install DPDK"
    exit -1
fi

########################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR: $errmsg"
        exit -1
    fi
}

########################################
##  Install pre-requisites (assuming the tool is available)

prereqs=()
prereqs+=( "wget@" )
prereqs+=( "tar@" )
prereqs+=( "sed@" )
prereqs+=( "gcc@build-essential" )
prereqs+=( "make@build-essential" )

# Ubuntu:
prereqs+=( "lua5.2@ubuntu:lua5.2" )
prereqs+=( "/usr/include/pcap/pcap.h@ubuntu:libpcap-dev,centos:libpcap-devel" )

if which install-packages.sh > /dev/null 2>&1 ; then
    install-packages.sh ${prereqs[@]}
        check_status "failed to install prerequisites"
fi

########################################
##  Try to find a local DPDK package

srchlist=()
srchlist+=( "$(pwd)" )
srchlist+=( "$HOME" )
srchlist+=( "/opt/download" )
srchlist+=( "/pkgs/dpdk" )
srchlist+=( "/tmp" )

if [ "$pkgfile" == "" ] && [ "$pkgdir" == "" ]; then
    for srchdir in ${srchlist[@]} ; do
        if [ -d "$srchdir" ]; then
            fn=$(find $srchdir -type f -name "$pkgname-$version.tar*" \
                | head -1)
            if [ "$fn" != "" ]; then
                pkgfile="$fn"
                break
            fi
        fi
    done
fi

########################################

if [ "$pkgfile" == "" ] && [ "$pkgdir" == "" ]; then
    dldir="/opt/download"
    url="http://dpdk.org/browse/apps/pktgen-dpdk/snapshot"
    fname="$pkgname-$version.tar.xz"
    mkdir -p $dldir
        check_status "failed to create $dldir"
    dlfile="$dldir/pend-$fname"
    echo " - Downloading $url/$fname"
    wget --no-verbose "$url/$fname" -O "$dlfile"
        check_status "failed to download $url/$fname"
    pkgfile="$dldir/$fname"
    /bin/mv -f "$dlfile" "$pkgfile"
        check_status "failed to move $dlfile"
fi

########################################

if [ "$version" == "" ]; then
    version=$(echo $pkgfile \
        | sed -r 's/^.*\/'$pkgname'-(\S+)\.tar.*$/\1/')
fi

########################################
tardir=$(tar t -f $pkgfile \
    | head -1 \
    | sed -r 's/\/$//')

    check_status "failed to determine package directory"

pkgdir="$srcdir/$tardir"

if [ -e $pkgdir ]; then
    # Clean-up previous Installation. Experience has shown that
    # the Makefiles do not properly handle a previous installation.
    /bin/rm -rf $pkgdir
        check_status "failed to remove $pkgdir"
fi

########################################
mkdir -p $srcdir

tar x -C $srcdir -f $pkgfile
    check_status "failed to un-tar $pkgfile"

tardir=$(tar t -f $pkgfile \
    | head -1 \
    | sed -r 's/\/$//')

    check_status "failed to determine package directory"

pkgdir="$srcdir/$tardir"

########################################

. /etc/dpdk.conf

########################################
##  HACK!!

touch $RTE_SDK/build/include/rte_bus_pci.h

########################################

export RTE_ARCH=
export RTE_OUTPUT="$HOME/.cache/dpdk/build/pktgen-$DPDK_VERSION-$version"
mkdir -p $RTE_OUTPUT

make -C $pkgdir

    check_status "failed making pktgen"

########################################
##  Save DPDK-pktgen settings

conffile="/etc/$pkgname-$version.conf"

execfile=$(find $pkgdir/app -name 'pktgen' -executable \
    | head -1)
test "$execfile" != ""
    check_status "failed to find pktgen executable"

( \
    echo "# Generated on $(date) by $0" ; \
    echo "export DPDK_PKTGEN_VERSION=$version" ; \
    echo "export DPDK_RTE_SDK=$RTE_SDK" ; \
    echo "export DPDK_RTE_TARGET=$RTE_TARGET" ; \
    echo "export DPDK_PKTGEN_DIR=$pkgdir" ; \
    echo "export DPDK_PKTGEN_EXEC=$execfile" ; \
) > $conffile

/bin/cp -f $conffile /etc/$pkgname.conf

########################################

exit 0
