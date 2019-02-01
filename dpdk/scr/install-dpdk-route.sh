#!/bin/bash

########################################
##  Defaults:

: ${NS_TOOLS_GIT_REPO_URL="https://github.com/netronome-support/Tools"}

if [ "$(whoami)" == "root" ]; then
    # Installation Directory
    : ${GIT_REPO_BASE_DIR:="/opt/src/netronome-support"}

    # No need for 'sudo'
    SUDO=""
else
    : ${GIT_REPO_BASE_DIR:="$HOME/build/git/netronome-support"}
    SUDO="sudo"
fi

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
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}

########################################
##  Install pre-requisites (assuming the tool is available)

prereqs=()
prereqs+=( "git@" )
prereqs+=( "gcc@build-essential" )
prereqs+=( "make@build-essential" )

if which install-packages.sh > /dev/null 2>&1 ; then
    install-packages.sh ${prereqs[@]}
        check_status "failed to install prerequisites"
fi

########################################

if [ -d $GIT_REPO_BASE_DIR/Tools ]; then
    cd $GIT_REPO_BASE_DIR/Tools
    git pull
    	check_status "failed to 'git pull' Tools repo"
else
    mkdir -p $GIT_REPO_BASE_DIR
        check_status "failed to create $GIT_REPO_BASE_DIR"
    cd $GIT_REPO_BASE_DIR
    git clone $NS_TOOLS_GIT_REPO_URL
        check_status "failed to clone $NS_TOOLS_GIT_REPO_URL"
fi

########################################

. /etc/dpdk.conf

########################################

rtdir="$GIT_REPO_BASE_DIR/Tools/dpdk/route"

test -d $rtdir
    check_status "missing route source code in repository"

make -C $rtdir
    check_status "failed to 'make' route source code"

$SUDO cp $rtdir/build/route /usr/local/bin/dpdk-route

########################################

exit 0
