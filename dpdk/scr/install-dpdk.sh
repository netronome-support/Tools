#!/bin/bash

########################################
##  Defaults:

# List of CONFIG_RTE_LIBRTE_ features to enable
: ${DPDK_CFG_LIBRTE_LIST:="NFP_PMD"}
# MLX4_PMD MLX5_PMD

# Compile Target Architecture for DPDK
: ${RTE_TARGET:="x86_64-native-linuxapp-gcc"}

# DPDK Web Site
: ${DPDK_DOWNLOAD_URL:="https://fast.dpdk.org/rel"}

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

pkgname="dpdk"
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
            "--list-set")       param="list-set" ;;
            "--list-add")       param="list-add" ;;
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
            "list-set")         DPDK_CFG_LIBRTE_LIST="$arg" ;;
            "list-add")         DPDK_CFG_LIBRTE_LIST="$DPDK_CFG_LIBRTE_LIST $arg" ;;
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

test "${version}${pkgfile}${pkgdir}" != ""
    check_status "please specify either version, package file, or package directory"

########################################

function check_installation () {
    if [ -f "$conffile" ]; then
        . $conffile
        test -d $RTE_SDK            || install="yes"
        test -f $DPDK_DEVBIND       || install="yes"
        test -f $DPDK_IGB_UIO_DRV   || install="yes"
    else
        install="yes"
    fi
}

########################################
if [ -f /etc/os-release ]; then
    OS_ID=$(cat /etc/os-release | sed -rn 's/^ID=(\S+)$/\1/p')
fi
########################################
##  Install pre-requisites (assuming the tool is available)

kvers=$(uname -r)

prereqs=()
prereqs+=( "wget@" )
prereqs+=( "tar@" )
prereqs+=( "sed@" )
prereqs+=( "gcc@" )
prereqs+=( "make@" )
prereqs+=( "python@" ) # needed by dpdk-devbind
prereqs+=( "lspci@pciutils" ) # needed by dpdk-devbind
# CentOS:
prereqs+=( "/usr/src/kernels/$kvers/include@centos:kernel-devel-$kvers" )
#prereqs+=( "/usr/src/kernels/$kvers/include@centos:kernel-devel" )

#case "$version" in
#    "17.11"|"17.11.2")
prereqs+=( "/usr/include/numa.h@ubuntu:libnuma-dev,centos:numactl-devel" )
#esac

if [ "$OS_ID" == "fedora" ]; then
    prereqs+=( "/usr/include/libelf.h@elfutils-libelf-devel" )
fi

########################################
##  Download 'install-packages.sh' script if missing

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

########################################

install-packages.sh ${prereqs[@]}
    check_status "failed to install prerequisites"

########################################

if [ "$version" != "" ]; then
    conffile="/etc/$pkgname-$version.conf"
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
    echo " - Download $DPDK_DOWNLOAD_URL/$fname"
    wget --no-verbose "$DPDK_DOWNLOAD_URL/$fname" -O "$dlfile"
        check_status "failed to download $DPDK_DOWNLOAD_URL/$fname"
    pkgfile="$DPDK_DOWNLOAD_DIR/$fname"
    mv -f "$dlfile" "$pkgfile"
        check_status "failed to move $dlfile"
fi

########################################

if [ "$version" == "" ]; then
    if [ "$pkgfile" != "" ]; then
        version=$(echo $pkgfile \
            | sed -r 's/^.*\/'$pkgname'-(\S+)\.tar.*$/\1/')
    elif [ -d $pkgdir/.git ]; then
        version=$(cd $pkgdir ; git log -1 --format="%H")
    else
        version=""
    fi
fi

########################################

conffile="$DPDK_SETTINGS_DIR/$pkgname-$version.conf"
check_installation

########################################
##  Stop here if it appears to already been installed

if [ "$install" == "" ]; then
    exit 0
fi

########################################

if [ "$pkgdir" == "" ]; then
    mkdir -p $DPDK_INSTALL_DIR
        check_status "failed to create $DPDK_INSTALL_DIR"

    tar x -C $DPDK_INSTALL_DIR -f $pkgfile
        check_status "failed to un-tar $pkgfile"

    tardir=$(tar t -f $pkgfile \
        | head -1 \
        | sed -r 's/\/$//')

        check_status "failed to determine package directory"

    pkgdir="$DPDK_INSTALL_DIR/$tardir"
fi

export RTE_SDK="$pkgdir"

########################################

opts=""
opts="$opts T=$RTE_TARGET"

########################################
##  Disable KNI (DPDK v16.11.3 does not build on CentOS 7.4)

ss=""
ss="${ss}s/^(CONFIG_RTE_KNI_KMOD).*$/\1=n/;"
ss="${ss}s/^(CONFIG_RTE_LIBRTE_KNI).*$/\1=n/;"
ss="${ss}s/^(CONFIG_RTE_LIBRTE_PMD_KNI).*$/\1=n/;"

sed -r "$ss" -i $RTE_SDK/config/common_linuxapp

########################################
##  Some bug fix

sed -r "s/(link.link_speed) = ETH_SPEED_NUM_NONE/\1 = 100000/" \
    -i $RTE_SDK/drivers/net/nfp/nfp_net.c \
    || exit -1

########################################

make -C $RTE_SDK config $opts

    check_status "failed to configure DPDK"

########################################
ss=""
########################################
for item in $DPDK_CFG_LIBRTE_LIST ; do
    ss="${ss}s/(CONFIG_RTE_LIBRTE_$item)=.*"'$/\1=y/;'
done
########################################
##  Custom configuration (via DPDK_CUSTOM_CONFIG)

idx=1
while : ; do
    config=$(echo "$DPDK_CUSTOM_CONFIG;" | cut -d ';' -f $idx)
    if [ "$config" == "" ]; then
        break
    fi
    varname=${config/=*/}
    value=${config/*=/}
    if [ "$varname" != "" ] && [ "$value" != "" ]; then
        ss="${ss}s/($varname)=.*\$/\1=$value/;"
    fi
    idx=$(( idx + 1 ))
done

########################################
cfglist=()
cfglist+=( "build/.config" )
cfglist+=( "config/common_linuxapp" )
cfglist+=( "config/common_base" )
for cfgfile in ${cfglist[@]} ; do
    sed -r "$ss" -i $RTE_SDK/$cfgfile
        check_status "failed to access $RTE_SDK/$cfgfile"
done

########################################
##  Save a copy of the configuration

buildconfig="$RTE_SDK/build/build.config"

if [ -f $buildconfig ]; then
    /bin/mv -f $buildconfig $buildconfig.old \
        || exit -1
fi
/bin/cp -f $RTE_SDK/build/.config \
    ${buildconfig}.pending \
    || exit -1

########################################

make -C $RTE_SDK \
    | tee $RTE_SDK/build/make.log

    check_status "failed to make DPDK"

########################################

if [ ! -d $DPDK_SETTINGS_DIR ]; then
    mkdir -p $DPDK_SETTINGS_DIR
        check_status "failed to create $DPDK_SETTINGS_DIR"
fi

########################################
##  Save DPDK settings

cat <<EOF > $conffile
# Generated on $(date) by $0
export RTE_SDK="$RTE_SDK"
export RTE_TARGET="$RTE_TARGET"
export DPDK_VERSION="$version"
export DPDK_DEVBIND="$devbind"
# List of enabled RTE components:
export DPDK_CFG_LIBRTE_LIST="$DPDK_CFG_LIBRTE_LIST"
export DPDK_BUILD_TIME="$(date +'%s')"
export DPDK_CONFIG="$buildconfig"
export DPDK_IGB_UIO_DRV="$igb_uio_drv_file"
EOF

########################################

$SUDO make -C $RTE_SDK install

    check_status "failed to install DPDK"

########################################
##  Move the pending build config

/bin/mv ${buildconfig}.pending $buildconfig \
    || exit -1

########################################

$SUDO depmod -a

########################################

# Not sure why this is needed, but I can't build other apps without it:
if [ ! -h $RTE_SDK/$RTE_TARGET ]; then
    ln -sf $RTE_SDK/build $RTE_SDK/$RTE_TARGET
fi

########################################
##  Locate the 'igb_uio' driver

igb_uio_drv_file=$(find $RTE_SDK -type f -name 'igb_uio.ko' \
    | head -1)

test "$igb_uio_drv_file" != ""
    check_status "build did not produce an igb_uio driver"

########################################

devbind=$(find $RTE_SDK -name 'dpdk-devbind.py' \
    | head -1)

if [ -f "$devbind" ]; then
    $SUDO cp -f $devbind /usr/local/bin

        check_status "failed to copy dpdk-devbind.py"
fi

########################################

cp -f $conffile $DPDK_SETTINGS_DIR/$pkgname.conf

$SUDO cp -f $conffile /etc
$SUDO cp -f $conffile /etc/$pkgname.conf

########################################

exit 0
