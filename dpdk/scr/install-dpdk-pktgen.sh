#!/bin/bash

for arg in "$@" ; do
    if [ "$param" == "" ]; then
        case "$arg" in
            "--help"|"-h")
                echo "Usage: <package file>|<version>"
                exit 0
                ;;
            "--verbose"|"-v")   optVerbose="yes" ;;
            "--reinstall")      REINSTALL="yes" ;;
            "--version")        param="version" ;;
            "--dpdk-version")   param="dpdk-version" ;;
        *)
            if [ -f "$arg" ]; then
                pkgfile="$arg"
            elif [ -d "$arg" ]; then
                pkgdir="$arg"
            else
                version="$arg"
            fi
            ;;
        esac
    else
        case "$param" in
            "version")          version="$arg" ;;
            "dpdk-version")     DPDK_VERSION="$arg" ;;
        esac
        param=""
    fi
done

########################################

if [ "${version}${pkgfile}${pkgdir}" == "" ]; then
    echo "ERROR: please specify either version, package file, or package directory"
    exit -1
fi

########################################

pkgname="pktgen"

# Installation Directory
: "${DPDK_INSTALL_DIR:=/opt/src}"

# DPDK Download Directory
: "${DPDK_DOWNLOAD_DIR:=/var/cache/download}"

# DPDK-pktgen Web Site
: "${PKTGEN_DOWNLOAD_URL:=http://dpdk.org/browse/apps/pktgen-dpdk/snapshot}"

########################################

dpdk_conf_file="/etc/dpdk.conf"

if [ "$DPDK_VERSION" != "" ]; then
    if [ -d "$RTE_SDK" ] && [ "$RTE_TARGET" != "" ]; then
        dpdk_conf_file=""
    else
        dpdk_conf_file="/etc/dpdk-$DPDK_VERSION.conf"
    fi
fi

if [ "$dpdk_conf_file" != "" ]; then
    if [ ! -f $dpdk_conf_file ]; then
        echo "ERROR: DPDK settings expected in $dpdk_conf_file"
        echo " - use install-dpdk.sh <version> to install DPDK"
        exit -1
    fi
    . $dpdk_conf_file
fi

########################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}

########################################
##  Install pre-requisites (assuming the tool is available)

prereqs=()
prereqs+=( "wget@" )
prereqs+=( "tar@" )
prereqs+=( "sed@" )
prereqs+=( "patch@" )
prereqs+=( "gcc@ubuntu:build-essential,centos:gcc" )
prereqs+=( "make@ubuntu:build-essential,centos:gcc" )

# Ubuntu:
prereqs+=( "lua5.2@ubuntu:lua5.2" )
prereqs+=( "/usr/include/pcap/pcap.h@ubuntu:libpcap-dev,centos:libpcap-devel" )

# Strange ... I had to manually install libpcap-dev

install-packages.sh ${prereqs[@]}
    check_status "failed to install prerequisites"

########################################

if [ "$version" != "" ]; then
    conffile="/etc/$pkgname-$DPDK_VERSION-$version.conf"

    if [ -f "$conffile" ] && [ "$REINSTALL" == "" ]; then
        exit 0
    fi
fi

########################################
##  Try to find a local DPDK package

srchlist=()
srchlist+=( "$(pwd)" )
srchlist+=( "$HOME" )
srchlist+=( "$DPDK_DOWNLOAD_DIR" )
srchlist+=( "/var/cache/download" )
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
    url="http://dpdk.org/browse/apps/pktgen-dpdk/snapshot"
    fname="$pkgname-$version.tar.xz"
    mkdir -p $DPDK_DOWNLOAD_DIR
        check_status "failed to create $DPDK_DOWNLOAD_DIR"
    dlfile="$DPDK_DOWNLOAD_DIR/pend-$fname"
    echo " - Downloading $PKTGEN_DOWNLOAD_URL/$fname"
    wget --no-verbose "$PKTGEN_DOWNLOAD_URL/$fname" -O "$dlfile"
        check_status "failed to download $PKTGEN_DOWNLOAD_URL/$fname"
    pkgfile="$DPDK_DOWNLOAD_DIR/$fname"
    /bin/mv -f "$dlfile" "$pkgfile"
        check_status "failed to move $dlfile"
fi

########################################

if [ "$version" == "" ]; then
    version=$(echo $pkgfile \
        | sed -r 's/^.*\/'$pkgname'-(\S+)\.tar.*$/\1/')
fi

########################################

conffile="/etc/$pkgname-$DPDK_VERSION-$version.conf"

if [ -f "$conffile" ] && [ "$REINSTALL" == "" ]; then
    exit 0
fi

########################################

if [ -f "$pkgfile" ]; then
    tardir=$(tar t -f $pkgfile \
        | head -1 \
        | sed -r 's/\/$//')

        check_status "failed to determine package directory"

    pkgdir="$DPDK_INSTALL_DIR/$tardir"

    if [ -e $pkgdir ]; then
        # Clean-up previous Installation. Experience has shown that
        # the Makefiles do not properly handle a previous installation.
        /bin/rm -rf $pkgdir
            check_status "failed to remove $pkgdir"
    fi

    mkdir -p $DPDK_INSTALL_DIR

    tar x -C $DPDK_INSTALL_DIR -f $pkgfile
        check_status "failed to un-tar $pkgfile"

    pkgdir="$DPDK_INSTALL_DIR/$tardir"
fi

########################################
##  HACK!!

touch $RTE_SDK/build/include/rte_bus_pci.h

########################################

export RTE_ARCH=
export RTE_OUTPUT="$HOME/.cache/dpdk/build/$pkgname-$DPDK_VERSION-$version"
mkdir -p $RTE_OUTPUT

make -C $pkgdir \
    | tee $RTE_OUTPUT/make.log

    check_status "failed making $pkgname"

########################################
##  Save DPDK-pktgen settings

execfile=$(find $pkgdir/app -name 'pktgen' -executable \
    | head -1)
test "$execfile" != ""
    check_status "failed to find pktgen executable"

( \
    echo "# Generated on $(date) by $0" ; \
    echo "export DPDK_PKTGEN_VERSION=$version" ; \
    echo "export DPDK_VERSION=$DPDK_VERSION" ; \
    echo "export DPDK_RTE_SDK=$RTE_SDK" ; \
    echo "export DPDK_RTE_TARGET=$RTE_TARGET" ; \
    echo "export DPDK_PKTGEN_DIR=$pkgdir" ; \
    echo "export DPDK_PKTGEN_EXEC=$execfile" ; \
) > $conffile

/bin/cp -f $conffile /etc/$pkgname.conf

########################################

exit 0
