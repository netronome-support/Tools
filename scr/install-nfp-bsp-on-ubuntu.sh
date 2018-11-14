#!/bin/bash

########################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR: $errmsg"
        exit -1
    fi
}

########################################

tmpdir=$(mktemp --directory --suffix '-install-nfp-bsp')

apt-get remove -y nfp-bsp nfp-bsp-dev \
    > $tmpdir/apt-remove.log 2>&1

########################################

keyfile="$tmpdir/key.asc"

wget -O $keyfile http://apt.pa.netronome.com/bbslave-pubkey.asc
    check_status "failed to download Netronome public key"

apt-key add $keyfile
    check_status "failed to add public key"

########################################

cat <<EOF > /etc/apt/sources.list.d/netronome.list
# Added by $0 on $(date)
deb http://apt.pa.netronome.com/ nfp stable
EOF

apt-get update
apt-get install -y nfp-bsp nfp-bsp-dev
    check_status "failed to install NFP BSP"

########################################

exit 0
