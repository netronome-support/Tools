#!/bin/bash

: "${TOOLS_DEST_DIR:=/usr/local/bin}"

if [ ! -w $TOOLS_DEST_DIR ]; then
    echo "ERROR: access denied to $TOOLS_DEST_DIR"
    echo "  - this script needs to be run as 'root'"
    exit -1
fi

tools_dir=$(dirname $0)

if [ ! -f $tools_dir/install.sh ]; then
    echo "ERROR: could not determine Tools repository location"
    exit -1
fi

opts=()
opts+=( "--force" )
opts+=( "--remove-destination" )

list=()
list+=( $(find $tools_dir/scr -type f) )
list+=( $(find $tools_dir/dpdk/scr -type f) )

cp ${opts[@]} ${list[@]} $TOOLS_DEST_DIR \
    || exit -1

# Install GCC
pkglist=()
pkglist+=( "gcc@" )
$TOOLS_DEST_DIR/install-packages.sh ${pkglist[@]} \
    || exit -1

gcc $tools_dir/src/rate.c -o $TOOLS_DEST_DIR/rate
gcc $tools_dir/src/ofrates.c -o $TOOLS_DEST_DIR/ofrates

echo "SUCCESS"
exit 0
