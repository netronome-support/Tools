#!/bin/bash

########################################

: "${NS_KEY_CACHE:=/var/cache/download/netronome/keys}"

########################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}

########################################

test -f /etc/os-release
    check_status "missing /etc/os-release on this system"

OS_ID="$(cat /etc/os-release \
    | sed -rn 's/^ID=//p' \
    | tr -d '"')"

########################################
which wget > /dev/null 2>&1
    check_status "'wget' is not installed"

########################################

case "$OS_ID" in
  "ubuntu")
    key_url="https://deb.netronome.com/gpg/NetronomePublic.key"
    key_install_cmd="apt-key add"
    mkdir -p /etc/apt/sources.list.d
    echo "deb https://deb.netronome.com/apt stable main" \
        > /etc/apt/sources.list.d/netronome.list
    ;;
  "centos"|"redhat"|"fedora")
    key_url="https://rpm.netronome.com/gpg/NetronomePublic.key"
    key_install_cmd="rpm --import"
    ;;
  *)
    echo "ERROR: unsupported OS ($OS_ID)"
    exit -1
esac

########################################

mkdir -p $NS_KEY_CACHE
    check_status "failed to create directory $NS_KEY_CACHE"

key_cache_file="$NS_KEY_CACHE/NetronomePublic-$OS_ID.key"

if [ ! -f $key_cache_file ]; then
    echo " - Download $key_url"
    wget --quiet $key_url -O $key_cache_file
        check_status "failed to download $key_url"
fi

########################################
echo " - Install Netronome Repository Key"

$key_install_cmd $key_cache_file
    check_status "failed to install key"

########################################

if [ -d /etc/yum.repos.d ]; then
cat <<EOF > /etc/yum.repos.d/netronome.repo
[netronome]
name=netronome
baseurl=https://rpm.netronome.com/repos/centos/
gpgcheck=0
enabled=1
EOF
fi

########################################

case "$OS_ID" in
  "ubuntu")
    apt-get update
        check_status "failed to 'apt-get update'"
    ;;
  "centos"|"redhat"|"fedora")
    yum makecache
        check_status "failed to 'yum makecache'"
    ;;
esac

########################################

exit 0
