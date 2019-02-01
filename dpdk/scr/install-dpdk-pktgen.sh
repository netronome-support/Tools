#!/bin/bash

########################################
##  Defaults:

# Compile Target Architecture for DPDK
: ${RTE_TARGET:="x86_64-native-linuxapp-gcc"}

# DPDK-pktgen Web Site
: "${PKTGEN_DOWNLOAD_URL:=http://dpdk.org/browse/apps/pktgen-dpdk/snapshot}"

if [ "$(whoami)" == "root" ]; then
    # Installation Directory
    : ${DPDK_INSTALL_DIR:="/opt/src"}

    # DPDK Download Directory
    : ${DPDK_DOWNLOAD_DIR:="/var/cache/download"}

    # DPDK Installation Parameter Directory
    : ${DPDK_SETTINGS_DIR:="/etc"}

    # No need for 'sudo'
    SUDO=""
else
    : ${DPDK_INSTALL_DIR:="$HOME/build"}
    : ${DPDK_DOWNLOAD_DIR:="$HOME/.cache/download"}
    : ${DPDK_SETTINGS_DIR:="$HOME/.config/dpdk"}
    SUDO="sudo"
fi

########################################
##  Parse command line

pkgname="pktgen"
install=""

for arg in "$@" ; do
    if [ "$param" == "" ]; then
        case "$arg" in
            "--help"|"-h")
                echo "Usage: <package file>|<version>"
                exit 0
                ;;
            "--verbose"|"-v")   optVerbose="yes" ;;
            "--reinstall")      install="yes" ;;
            "--force")          install="yes" ;;
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

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}

########################################

if [ "${version}${pkgfile}${pkgdir}" == "" ]; then
    echo "ERROR: please specify either version, package file, or package directory"
    exit -1
fi

########################################

dpdk_conf_file="$DPDK_SETTINGS_DIR/dpdk.conf"

if [ "$DPDK_VERSION" != "" ]; then
    if [ -d "$RTE_SDK" ] && [ "$RTE_TARGET" != "" ]; then
        dpdk_conf_file=""
    else
        dpdk_conf_file="$DPDK_SETTINGS_DIR/dpdk-$DPDK_VERSION.conf"
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
function check_installation () {
    if [ -f "$conffile" ]; then
        . $conffile
        test -d $DPDK_PKTGEN_DIR    || install="yes"
        test -f $DPDK_PKTGEN_EXEC   || install="yes"
        if [ "$DPDK_BUILD_TIME" != "" ]; then
            if [ $DPDK_BUILD_TIME -gt $DPDK_PKTGEN_BUILD_TIME ]; then
                install="yes"
            fi
        fi
    else
        install="yes"
    fi
}
########################################

which install-packages.sh > /dev/null 2>&1
    check_status "missing 'install-packages.sh'"

########################################
if [ -f /etc/os-release ]; then
    OS_ID=$(cat /etc/os-release | sed -rn 's/^ID=(\S+)$/\1/p')
    OS_VERSION=$(cat /etc/os-release | sed -rn 's/^VERSION_ID=(\S+)$/\1/p')
fi
########################################
##  Install pre-requisites (assuming the tool is available)

prereqs=()
prereqs+=( "wget@" )
prereqs+=( "tar@" )
prereqs+=( "sed@" )
prereqs+=( "patch@" )
prereqs+=( "gcc@ubuntu:build-essential,centos:gcc" )
prereqs+=( "make@ubuntu:build-essential,centos:gcc" )

case "$OS_ID" in
  "ubuntu")
    prereqs+=( "lua5.2@lua5.2" )
    case "$OS_VERSION" in
        "18.04") prereqs+=( "/usr/include/lua5.3/lua.h@liblua5.3-dev" ) ;;
    esac
    ;;
  "fedora")
    prereqs+=( "lua@" )
    prereqs+=( "/usr/include/lua.h@lua-devel" )
    ;;
esac

prereqs+=( "/usr/include/pcap/pcap.h@ubuntu:libpcap-dev,centos:libpcap-devel" )

# Strange ... I had to manually install libpcap-dev

install-packages.sh ${prereqs[@]}
    check_status "failed to install prerequisites"

########################################

if [ "$OS_ID" == "fedora" ]; then
    $SUDO cp -f /usr/lib64/pkgconfig/lua.pc /usr/lib64/pkgconfig/lua5.3.pc
fi

########################################

if [ "$version" != "" ]; then
    conffile="$DPDK_SETTINGS_DIR/$pkgname-$DPDK_VERSION-$version.conf"
    check_installation

    if [ "$install" == "" ]; then
        exit 0
    fi
fi

########################################
##  Try to find a local DPDK package

srchlist=()
srchlist+=( "$DPDK_DOWNLOAD_DIR" )
srchlist+=( "$(pwd)" )
srchlist+=( "$HOME" )
srchlist+=( "/var/cache/download" )
srchlist+=( "/opt/download" )
srchlist+=( "/pkgs/dpdk" )
srchlist+=( "/tmp" )

if [ "$pkgfile" == "" ] && [ "$pkgdir" == "" ]; then
    for srchdir in ${srchlist[@]} ; do
        if [ -d "$srchdir" ]; then
            fn=$(find $srchdir -maxdepth 1 -type f -name "$pkgname-$version.tar*" \
                | head -1)
            if [ "$fn" != "" ]; then
                pkgfile="$fn"
                break
            fi
        fi
    done
    if [ "$pkgfile" != "" ]; then
        echo " - Found $pkgname package at $pkgfile"
    fi
fi

########################################

if [ "$pkgfile" == "" ] && [ "$pkgdir" == "" ]; then
    fname="$pkgname-$version.tar.xz"
    mkdir -p $DPDK_DOWNLOAD_DIR
        check_status "failed to create $DPDK_DOWNLOAD_DIR"
    dlfile="$DPDK_DOWNLOAD_DIR/pend-$fname"
    echo " - Downloading $PKTGEN_DOWNLOAD_URL/$fname"
    wget --quiet --no-verbose "$PKTGEN_DOWNLOAD_URL/$fname" -O "$dlfile"
        check_status "failed to download $PKTGEN_DOWNLOAD_URL/$fname"
    pkgfile="$DPDK_DOWNLOAD_DIR/$fname"
    mv -f "$dlfile" "$pkgfile"
        check_status "failed to move $dlfile"
fi

########################################

if [ "$version" == "" ]; then
    version=$(echo $pkgfile \
        | sed -r 's/^.*\/'$pkgname'-(\S+)\.tar.*$/\1/')
fi

########################################

conffile="$DPDK_SETTINGS_DIR/$pkgname-$DPDK_VERSION-$version.conf"
check_installation

########################################
##  Stop here if it appears to already been installed

if [ "$install" == "" ]; then
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
test -d $RTE_SDK
    check_status "missing DPDK installation"
test "$RTE_TARGET" != ""
    check_status "RTE_TARGET is not set"
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

cat <<EOF > $conffile
# Generated on $(date) by $0
export DPDK_PKTGEN_VERSION="$version"
export DPDK_VERSION="$DPDK_VERSION"
export DPDK_RTE_SDK="$RTE_SDK"
export DPDK_RTE_TARGET="$RTE_TARGET"
export DPDK_PKTGEN_DIR="$pkgdir"
export DPDK_PKTGEN_EXEC="$execfile"
export DPDK_PKTGEN_BUILD_TIME="$(date +'%s')"
EOF

########################################

cp -f $conffile $DPDK_SETTINGS_DIR/$pkgname.conf

$SUDO cp -f $conffile /etc
$SUDO cp -f $conffile /etc/$pkgname.conf

########################################

exit 0
