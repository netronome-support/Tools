#!/bin/bash

########################################################################
##  Install 'ethtool' if it is missing

install-packages.sh "ethtool@" \
    || exit -1

########################################################################
##  Collect all interfaces on the system

list=$(cat /proc/net/dev \
    | sed -rn 's/^\s*(\S+):.*$/\1/p' \
    | sort \
    )

########################################################################
##  Structure the order to make more readable

declare -A ifset
iflist=()

for iface in $list ; do
    re_nfp='^nfp_v[0-9]\.[0-9]{1,2}$'
    if [ "$iface" == "lo" ]; then
        :
    elif [[ ! "$iface" =~ $re_nfp ]]; then
        iflist+=( "$iface" )
    else
        ifset[$iface]="Y"
    fi
done

for bus in 0 1 2 3 ; do
    for vfidx in $(seq 0 63) ; do
        ifname="nfp_v${bus}.${vfidx}"
        if [ "${ifset[$ifname]}" != "" ]; then
            iflist+=( "$ifname" )
        fi
    done
done

########################################################################
##  List interfaces with their driver and bus-info

for iface in ${iflist[@]} ; do
    info=$(ethtool -i $iface 2> /dev/null \
        | tr '\n' '@')
    drv=$(echo $info \
        | sed -rn 's/^.*driver:\s*(\S+)@.*$/\1/p')
    opt=$(echo $info \
        | sed -rn 's/^.*@bus-info: ([^@]*)@.*$/\1/p')
    if [ "$opt" == "" ]; then
        ppfile="/sys/class/net/$iface/phys_port_name"
        if [ -f $ppfile ]; then
            phys_port=$(cat $ppfile 2> /dev/null)
            if [ "$phys_port" != "" ]; then
                opt="- $phys_port"
            fi
        fi
    fi
    printf "  %-16s %-16s %s\n" "$iface" "$drv" "$opt"
done

########################################################################

exit 0
