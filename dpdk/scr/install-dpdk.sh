#!/bin/bash

install=""
list="NFP_PMD"
# MLX4_PMD MLX5_PMD
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
            "list-set")         list="$arg" ;;
            "list-add")         list="$list $arg" ;;
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

pkgname="dpdk"

# Installation Directory
: "${DPDK_INSTALL_DIR:=/opt/src}"

# Compile Target Architecture for DPDK
: "${RTE_TARGET:=x86_64-native-linuxapp-gcc}"

# DPDK Download Directory
: "${DPDK_DOWNLOAD_DIR:=/var/cache/download}"

# DPDK Web Site
: "${DPDK_DOWNLOAD_URL:=https://fast.dpdk.org/rel}"

########################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}

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
OS_ID=$(cat /etc/os-release | sed -rn 's/^ID=(\S+)$/\1/p')
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

prereqs+=( "/usr/include/numa.h@ubuntu:libnuma-dev,centos:numactl-devel" )

if [ "$OS_ID" == "fedora" ]; then
    prereqs+=( "/usr/include/libelf.h@elfutils-libelf-devel" )
fi

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
    fname="$pkgname-$version.tar.xz"
    mkdir -p $DPDK_DOWNLOAD_DIR
        check_status "failed to create $DPDK_DOWNLOAD_DIR"
    dlfile="$DPDK_DOWNLOAD_DIR/pend-$fname"
    echo " - Downloading $DPDK_DOWNLOAD_URL/$fname"
    wget --no-verbose "$DPDK_DOWNLOAD_URL/$fname" -O "$dlfile"
        check_status "failed to download $DPDK_DOWNLOAD_URL/$fname"
    pkgfile="$DPDK_DOWNLOAD_DIR/$fname"
    /bin/mv -f "$dlfile" "$pkgfile"
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

conffile="/etc/$pkgname-$version.conf"
check_installation

if [ "$install" == "" ]; then
    exit 0
fi

########################################

if [ "$pkgdir" == "" ]; then
    mkdir -p $DPDK_INSTALL_DIR

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

# Needed for DPDK-DAQ installation:
if [ "$BUILD_FOR_DPDK_DAQ" != "" ]; then
    echo "export EXTRA_CFLAGS=-O0 -fPIC -g" \
        >> $RTE_SDK/mk/rte.vars.mk
    opts="$opts CONFIG_RTE_BUILD_COMBINE_LIBS=y"
    opts="$opts CONFIG_RTE_BUILD_SHARED_LIB=y"
    opts="$opts EXTRA_CFLAGS=\"-fPIC\""
fi

########################################
# Disable KNI (DPDK v16.11.3 does not build on CentOS 7.4)

ss=""
ss="${ss}s/^(CONFIG_RTE_KNI_KMOD).*$/\1=n/;"
ss="${ss}s/^(CONFIG_RTE_LIBRTE_KNI).*$/\1=n/;"
ss="${ss}s/^(CONFIG_RTE_LIBRTE_PMD_KNI).*$/\1=n/;"

sed -r "$ss" -i $RTE_SDK/config/common_linuxapp

########################################
# Some bug fix

sed -r "s/(link.link_speed) = ETH_SPEED_NUM_NONE/\1 = 100000/" \
    -i $RTE_SDK/drivers/net/nfp/nfp_net.c \
    || exit -1

########################################

make -C $RTE_SDK config $opts

    check_status "failed to configure DPDK"

########################################
ss=""
########################################
for item in $list ; do
    ss="${ss}s/(CONFIG_RTE_LIBRTE_$item)=.*"'$/\1=y/;'
done
########################################
# Custom configuration (via DPDK_CUSTOM_CONFIG)

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
# Save a copy of the configuration

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

make -C $RTE_SDK install

    check_status "failed to install DPDK"

########################################
# Move the pending build config

/bin/mv ${buildconfig}.pending $buildconfig \
    || exit -1

########################################

depmod -a

########################################

# Not sure why this is needed, but I can't build other apps without it:
if [ ! -h $RTE_SDK/$RTE_TARGET ]; then
    ln -sf $RTE_SDK/build $RTE_SDK/$RTE_TARGET
fi

########################################
# Locate the 'igb_uio' driver

igb_uio_drv_file=$(find $RTE_SDK -type f -name 'igb_uio.ko' \
    | head -1)

test "$igb_uio_drv_file" != ""
    check_status "build did not produce an igb_uio driver"

########################################

devbind=$(find $RTE_SDK -name 'dpdk-devbind.py' \
    | head -1)

if [ -f "$devbind" ]; then
    cp -f $devbind /usr/local/bin

        check_status "failed to copy dpdk-devbind.py"
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
export DPDK_BUILD_LIST="$list"
export DPDK_BUILD_TIME="$(date +'%s')"
export DPDK_CONFIG="$buildconfig"
export DPDK_IGB_UIO_DRV="$igb_uio_drv_file"
EOF

/bin/cp -f $conffile /etc/$pkgname.conf

########################################

exit 0
