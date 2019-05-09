#!/bin/bash

rule=()
rule+=( 'SUBSYSTEM=="net",' )
rule+=( 'ACTION=="add",' )
# The first (management) interface is assumed to be created
# in the following PCI slot:
rule+=( 'KERNELS=="0000:00:02.0",' )
rule+=( 'NAME="mgmt"' )
echo "${rule[@]}" > /etc/udev/rules.d/10-mgmt-iface.rules

ifcfg_dir="/etc/sysconfig/network-scripts"
ifcfg_list=( $(find $ifcfg_dir -type f -name 'ifcfg-*' \
    | grep -v 'ifcfg-lo' \
    ) )

if [ ${#ifcfg_list[@]} -gt 0 ]; then
    sed -r 's/^ONBOOT=.*$/ONBOOT=yes/' \
        -i ${ifcfg_list[@]} \
        || exit -1
fi

cat <<EOF > $ifcfg_dir/ifcfg-mgmt
# Created by $0 on $(date)

# This interface is created by the udev rule defined in
# /etc/udev/rules.d/10-mgmt-iface.rules

# This interface should have been managed by cloud-init, but
# something isn't working properly, leading to this work-around.

BOOTPROTO=dhcp
DEVICE=mgmt
ONBOOT=yes
TYPE=Ethernet
USERCTL=no

EOF

exit 0
