#!/bin/bash

########################################################################

: "${VM_BUILD_DPDK_VERSION:=19.02}"
: "${VM_BUILD_DPDK_PKTGEN_VERSION:=3.5.0}"

########################################################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        if [ "$errmsg" != "" ]; then
            echo "ERROR($(basename $0)): $errmsg"
        fi
        exit -1
    fi
}

########################################################################
touch $HOME/.hushlogin
########################################################################
mkdir -p /etc/netplan
mkdir -p /etc/cloud/cloud.cfg.d

cat <<EOF > $rfsdir/etc/netplan/80-base-vm-interfaces.yaml
network:
    version: 2
    ethernets:
        id0:
            match: 
                name: en*
            dhcp4: true
            optional: true
EOF

cat <<EOF > $rfsdir/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
network: {config: disabled}
EOF

########################################################################
##  Packages to install on the VM

pkgs=()
pkgs+=( "git" "wget" "strace" "gawk" "unzip" "zip" "bc" )
pkgs+=( "expect" )
pkgs+=( "ntp" )
pkgs+=( "tmux" )
pkgs+=( "tcpdump" )
pkgs+=( "iperf3" )
pkgs+=( "ifupdown" )
pkgs+=( "pciutils" "python" ) # dpdk-devbind
pkgs+=( "socat" ) # dpdk-pktgen
pkgs+=( "vnstat" ) # Interface Rate Testing tool
pkgs+=( "hping3" ) # TCP-based ping
pkgs+=( "bwm-ng" ) # Bandwidth Monitoring Tool
pkgs+=( "fping" ) # Bandwidth Monitoring Tool

########################################################################

install-netronome-support-tools.sh
    check_status

install-packages.sh --update ${pkgs[@]}
    check_status

########################################################################
systemctl is-enabled ntp > /dev/null 2>&1 \
    && systemctl disable ntp

install-nfp-drv-kmods.sh
    check_status

install-dpdk.sh $VM_BUILD_DPDK_VERSION
    check_status

########################################################################

exit 0