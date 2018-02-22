#!/bin/bash

url="https://github.com/netronome-support/Tools"

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
prereqs+=( "git@" )
prereqs+=( "gcc@build-essential" )
prereqs+=( "make@build-essential" )

if which install-packages.sh > /dev/null 2>&1 ; then
    install-packages.sh ${prereqs[@]}
        check_status "failed to install prerequisites"
fi

########################################

nssdir="/opt/src/netronome-support"
mkdir -p $nssdir

if [ -d $nssdir/Tools ]; then
    cd $nssdir/Tools
    git pull \
        || exit -1
else
    cd $nssdir
    git clone $url \
        || exit -1
fi

########################################

. /etc/dpdk.conf

########################################

rtdir="$nssdir/Tools/dpdk/route"

test -d $rtdir

    check_status "missing route source code in repository"


make -C $rtdir \
    || exit -1

cp $rtdir/build/route /usr/local/bin/dpdk-route

exit 0
