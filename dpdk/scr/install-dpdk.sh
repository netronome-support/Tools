#!/bin/bash

########################################
##  Defaults:

# List of CONFIG_RTE_LIBRTE_ features to enable
: ${DPDK_CFG_LIBRTE_LIST:="NFP_PMD"}
# MLX4_PMD MLX5_PMD

# To explicitly set RTE_TARGET, FORCE_RTE_TARGET must be set
if [ "$FORCE_RTE_TARGET" != "" ]; then
    RTE_TARGET="$FORCE_RTE_TARGET"
else
    RTE_TARGET="x86_64-native-linuxapp-gcc"
fi
# On some systems RTE_TARGET is already set to
# 'x86_64-default-linuxapp-gcc' but at lease dpdk-17.11
# will not compile with this.

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

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}

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
            "--build-only")     optSkipInstall="yes" ;;
            "--skip-install")   optSkipInstall="yes" ;;
            "--reinstall")      install="yes" ;;
            "--force")          install="yes" ;;
            "--version")        param="version" ;;
            "--list-set")       param="list-set" ;;
            "--list-add")       param="list-add" ;;
        *)
            test "${arg:0:1}" != "-"
                check_status "failed to parse '$arg'"
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

test "$param" == ""
    check_status "argument missing for '--$param'"

########################################
set -o pipefail
########################################

test "${version}${pkgfile}${pkgdir}" != ""
    check_status "please specify either version, package file, or package directory"

########################################

function check_installation () {
    local fname="$1"
    if [ ! -f "$fname" ]; then
        install="yes"
        return
    fi
    mapfile -t cfglist < \
       <( cat $fname \
        | sed -r 's/^\s*export\s+//' \
        | sed -r 's/\s*#.*$//' \
        | sed '/^$/d' \
        | tr -d '\"' \
        )
    declare -A oldcfg
    oldcfg={}
    for entry in "${cfglist[@]}" ; do
        oldcfg[${entry/=*}]="${entry/*=}"
    done
    if  [ "${oldcfg[RTE_SDK]}" == "" ] ||
        [ "${oldcfg[RTE_TARGET]}" == "" ] ||
        [ ! -d "${oldcfg[RTE_SDK]}" ] ||
        [ ! -f "${oldcfg[DPDK_IGB_UIO_DRV]}" ] ||
        [ "${oldcfg[RTE_TARGET]}" != "$RTE_TARGET" ] ||
        [ "${oldcfg[DPDK_VERSION]}" != "$version" ] ||
        [ "${oldcfg[DPDK_BUILD_KERNEL]}" != "$(uname -r)" ];
    then
        install="yes"
    fi
    for feature in $DPDK_CFG_LIBRTE_LIST ; do
        echo " ${oldcfg[DPDK_CFG_LIBRTE_LIST]} " \
            | grep -E "\s$feature\s" > /dev/null
        if [ $? -ne 0 ]; then
            install="yes"
        fi
    done
}

########################################
if [ -f /etc/os-release ]; then
    OS_ID=$(cat /etc/os-release | sed -rn 's/^ID=(\S+)$/\1/p')
fi
########################################
##  Install pre-requisites (assuming the tool is available)

kvers=$(uname -r)

prereqs=()
prereqs+=( "wget" )
prereqs+=( "tar" )
prereqs+=( "sed" )
prereqs+=( "gcc" )
prereqs+=( "make" )
prereqs+=( "pkg-config" )
prereqs+=( "python" ) # needed by dpdk-devbind
prereqs+=( "pciutils" ) # needed by dpdk-devbind (lspci)

prereqs+=( "libnuma-DEVEL" )

case "$OS_ID" in
    "centos"|"fedora"|"rhel")
        prereqs+=( "kernel-devel-$kvers" )
        ;;
    "ubuntu"|"debian")
        # For Mellanox Driver:
        prereqs+=( "libibverbs-dev" )
        prereqs+=( "libmnl-dev" )
        ;;
esac

if [ "$OS_ID" == "fedora" ]; then
    prereqs+=( "elfutils-libelf-devel" )
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

install-packages.sh ${prereqs[@]} --update
    check_status "failed to install prerequisites"

########################################

if [ "$version" != "" ]; then
    conffile="/etc/$pkgname-$version.conf"
    check_installation "$conffile"

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
check_installation "$conffile"

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
        | sed -r 's/\/$//' ; true)

        check_status "failed to determine package directory"

    pkgdir="$DPDK_INSTALL_DIR/$tardir"
fi

export RTE_SDK="$pkgdir"

########################################

opts=()
opts+=( "-C" "$RTE_SDK" )
opts+=( "T=$RTE_TARGET" )

########################################
##  Disable KNI (DPDK v16.11.3 does not build on CentOS 7.4)

ss=""
ss="${ss}s/^(CONFIG_RTE_KNI_KMOD).*$/\1=n/;"
ss="${ss}s/^(CONFIG_RTE_LIBRTE_KNI).*$/\1=n/;"
ss="${ss}s/^(CONFIG_RTE_LIBRTE_PMD_KNI).*$/\1=n/;"

for fname in common_linuxapp common_base common_linux ; do
    cfgfile="$RTE_SDK/config/$fname"
    if [ -f $fname ]; then
        sed -r "$ss" -i $cfgfile
    fi
done

########################################
##  Some bug fix

sed -r "s/(link.link_speed) = ETH_SPEED_NUM_NONE/\1 = 100000/" \
    -i $RTE_SDK/drivers/net/nfp/nfp_net.c \
    || exit -1

sed -r 's/^(CONFIG_RTE_MAX_ETHPORTS)=.*$/\1=64/' \
    -i $RTE_SDK/config/common_base \
    || exit -1

########################################

mkdir -p $RTE_SDK/build

make ${opts[@]} config 2>&1 \
    | tee $RTE_SDK/build/config.log

    check_status "failed to configure DPDK"

########################################
# Remove Duplicates
DPDK_CFG_LIBRTE_LIST=( $(printf "%s\n" $DPDK_CFG_LIBRTE_LIST \
    | sort -u ) )
########################################
ss=""
########################################
for item in ${DPDK_CFG_LIBRTE_LIST[@]} ; do
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
    if [ -f $RTE_SDK/$cfgfile ]; then
        sed -r "$ss" -i $RTE_SDK/$cfgfile
            check_status "failed to access $RTE_SDK/$cfgfile"
    fi
done

########################################
##  Save a copy of the configuration

buildconfig="$RTE_SDK/build/build.config"

if [ -f $buildconfig ]; then
    mv -f $buildconfig $buildconfig.old \
        || exit -1
fi
cp -f $RTE_SDK/build/.config ${buildconfig}.pending
    check_status "failed to 'cp -f $RTE_SDK/build/.config ${buildconfig}.pending'"

########################################

make -C $RTE_SDK --jobs $(nproc) 2>&1 \
    | tee $RTE_SDK/build/make.log

    check_status "failed to make DPDK"

########################################

if [ ! -d $DPDK_SETTINGS_DIR ]; then
    mkdir -p $DPDK_SETTINGS_DIR
        check_status "failed to create $DPDK_SETTINGS_DIR"
fi

########################################
##  Locate the 'igb_uio' driver

igb_uio_drv_file=$(find $RTE_SDK -type f -name 'igb_uio.ko' \
    | head -1)

test "$igb_uio_drv_file" != ""
    check_status "build did not produce an igb_uio driver"

########################################
##  Locate the 'dpdk-devbind.py' driver

DPDK_DEVBIND=$(find $RTE_SDK -name 'dpdk-devbind.py' \
    | head -1)

########################################
##  Save DPDK settings

cat <<EOF > $conffile
# Generated on $(date) by $0
export RTE_SDK="$RTE_SDK"
export RTE_TARGET="$RTE_TARGET"
export DPDK_VERSION="$version"
export DPDK_CFG_LIBRTE_LIST="${DPDK_CFG_LIBRTE_LIST[@]}"
export DPDK_BUILD_TIME="$(date +'%s')"
export DPDK_BUILD_KERNEL="$(uname -r)"
export DPDK_CONFIG="$buildconfig"
export DPDK_IGB_UIO_DRV="$igb_uio_drv_file"
export DPDK_DEVBIND="$DPDK_DEVBIND"
EOF

########################################

if [ "$optSkipInstall" == "" ]; then
    $SUDO make -C $RTE_SDK install 2>&1 \
        | tee $RTE_SDK/build/install.log
        check_status "failed to install DPDK"
    $SUDO depmod -a
fi

########################################
##  Move the pending build config

mv ${buildconfig}.pending $buildconfig
    check_status "failed to 'mv ${buildconfig}.pending $buildconfig'"

########################################

# Not sure why this is needed, but I can't build other apps without it:
if [ ! -h $RTE_SDK/$RTE_TARGET ]; then
    ln -sf $RTE_SDK/build $RTE_SDK/$RTE_TARGET
fi

########################################

if [ -f "$DPDK_DEVBIND" ] && [ "$optSkipBuild" == "" ]; then
    $SUDO cp -f $DPDK_DEVBIND /usr/local/bin

        check_status "failed to copy dpdk-devbind.py"
fi

########################################

cp -f --remove-destination $conffile $DPDK_SETTINGS_DIR/$pkgname.conf

if [ "$DPDK_SETTINGS_DIR" != "/etc" ]; then
    $SUDO cp -f $conffile /etc
    $SUDO cp -f $conffile /etc/$pkgname.conf
fi

########################################

exit 0
