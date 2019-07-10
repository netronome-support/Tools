#!/bin/bash

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
##  Defaults:

pkgname="prox"

if [ "$(whoami)" == "root" ]; then
    # Installation Directory
    : ${GIT_REPO_BASE_DIR:="/opt/git"}
    : ${SRC_PKG_BASE_DIR:="/opt/src"}

    # No need for 'sudo'
    SUDO=""
else
    : ${GIT_REPO_BASE_DIR:="$HOME/git"}
    : ${SRC_PKG_BASE_DIR:="$HOME/src"}
    SUDO="sudo"
fi

########################################

if [ "$DPDK_VERSION" != "" ]; then
    if [ -d "$RTE_SDK" ] && [ "$RTE_TARGET" != "" ]; then
        dpdk_conf_file=""
    else
        dpdk_conf_file="/etc/dpdk-$DPDK_VERSION.conf"
    fi
else
    dpdk_conf_file="/etc/dpdk.conf"
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

function check_installation () {
    if [ -f "$conffile" ]; then
        . $conffile
        test -d $DPDK_PROX_DIR      || install="yes"
        test -f $DPDK_PROX_EXEC     || install="yes"
        test -f $DPDK_IGB_UIO_DRV   || install="yes"
        if [ "$DPDK_BUILD_TIME" != "" ]; then
            if [ $DPDK_BUILD_TIME -gt $DPDK_PROX_BUILD_TIME ]; then
                install="yes"
            fi
        fi
    else
        install="yes"
    fi
}
########################################
##  Install pre-requisites (assuming the tool is available)

pkgs=()
pkgs+=( "wget@" )
pkgs+=( "tar@" )
pkgs+=( "sed@" )
pkgs+=( "git@" )
pkgs+=( "gcc@build-essential" )
pkgs+=( "make@build-essential" )
pkgs+=( "pkg-config@" )

pkgs+=( "/usr/include/lua.h@redhat:lua-devel" )
pkgs+=( "pcap-config@redhat:libpcap-devel" )
pkgs+=( "/usr/include/ncurses.h@redhat:ncurses-devel" )
pkgs+=( "/usr/lib64/libedit.so@redhat:libedit-devel" )

pkgs+=( "/usr/include/lua5.1/lua.h@ubuntu:liblua5.1-0-dev" )
pkgs+=( "/usr/include/lua5.2/lua.h@ubuntu:liblua5.2-dev" )
pkgs+=( "lua5.2@ubuntu:lua5.2" )
pkgs+=( "pcap-config@ubuntu:libpcap0.8-dev" )
pkgs+=( "ncurses5-config@ubuntu:libncurses5-dev" )
pkgs+=( "/usr/lib/x86_64-linux-gnu/libedit.a@ubuntu:libedit-dev" )
pkgs+=( "ncursesw5-config@ubuntu:libncursesw5-dev" )

which install-packages.sh > /dev/null 2>&1
    check_status "missing 'install-packages.sh' script"

install-packages.sh --cache-update ${pkgs[@]}
    check_status "failed to install prerequisites"

########################################
if [ "$pkgfile" != "" ]; then
    mkdir -p $SRC_PKG_BASE_DIR
        check_status "failed to create directory $SRC_PKG_BASE_DIR"
    tar x -C $SRC_PKG_BASE_DIR -f $pkgfile
        check_status "failed to expand '$pkgfile'"
    tar_root_dir="$(tar tf $pkgfile | head -1)"
        check_status "failed to extract root dir from package '$pkgfile'"
    pkgdir="$SRC_PKG_BASE_DIR/$tar_root_dir"
    test -d $pkgdir
        check_status "failed to determine package base directory"
    version="$(basename $pkgfile)"
fi
########################################

if [ "$pkgdir" != "" ]; then
    proxdir="$pkgdir"
else
    mkdir -p $GIT_REPO_BASE_DIR

    git_repo_name="samplevnf"
    git_repo_dir="$GIT_REPO_BASE_DIR/$git_repo_name"

    url="https://git.opnfv.org/$git_repo_name"

    if [ -d $git_repo_dir ]; then
        set -o pipefail
        c_branch=$(git -C $git_repo_dir branch \
            | sed -rn 's/^\*\s+(\S+)$/\1/p')
            check_status "git could not determine branch"
        if [ "$c_branch" != "master" ]; then
            git -C $git_repo_dir checkout master > /dev/null
                check_status "failed to checkout master branch"
        fi
        git -C $git_repo_dir pull > /dev/null
            check_status "failed to pull PROX repository"
    else
        git clone $url $git_repo_dir
            check_status "failed to clone PROX repository"
    fi

    if [ "$version" != "" ]; then
        git -C $git_repo_dir branch -D $version > /dev/null 2>&1
        git -C $git_repo_dir checkout -b $version > /dev/null
            check_status "failed to checkout '$version'"
        git_tag="$(git -C $git_repo_dir describe --tags)"
    fi

    proxdir=$(find $git_repo_dir -type d -name 'DPPD-PROX')
fi

########################################

conffile="/etc/$pkgname-$DPDK_VERSION-$version.conf"
check_installation

if [ "$install" == "" ]; then
    exit 0
fi

########################################

test ! -z "$proxdir"
    check_status "could not find DPPD-PROX directory in GIT repo"

# pkgdir="$GIT_REPO_BASE_DIR/samplevnf"

########################################
test -d $RTE_SDK
    check_status "missing DPDK installation"
test "$RTE_TARGET" != ""
    check_status "RTE_TARGET is not set"
########################################

RTE_OUTPUT="$HOME/.cache/dpdk/build/$pkgname"
if [ "$DPDK_VERSION" != "" ]; then
    RTE_OUTPUT="$RTE_OUTPUT-$DPDK_VERSION"
fi
if [ "$version" != "" ]; then
    RTE_OUTPUT="$RTE_OUTPUT-$version"
fi
export RTE_ARCH=
export RTE_OUTPUT
mkdir -p $RTE_OUTPUT

########################################

make -C $proxdir \
    | tee $RTE_OUTPUT/make.log

    check_status "failed making $pkgname"

make -C $proxdir install \
    | tee -a $RTE_OUTPUT/make.log

    check_status "failed installing $pkgname"

########################################
##  Save DPDK-prox settings

execfile="$RTE_OUTPUT/prox"

cp --remove-destination $execfile /usr/local/bin
    check_status "failed to copy prox binary to /usr/local/bin"

cat <<EOF > $conffile
# Generated on $(date) by $0
export DPDK_PROX_VERSION=$version
export DPDK_PROX_GIT_TAG=$git_tag
export DPDK_VERSION=$DPDK_VERSION
export DPDK_RTE_SDK=$RTE_SDK
export DPDK_RTE_TARGET=$RTE_TARGET
export DPDK_PROX_DIR=$proxdir
export DPDK_PROX_EXEC=$execfile
export DPDK_PROX_BUILD_TIME="$(date +'%s')"
EOF

/bin/cp -f $conffile /etc/$pkgname.conf

########################################

exit 0
