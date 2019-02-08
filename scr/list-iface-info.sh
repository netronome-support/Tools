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
xd='[0-9a-fA-F]'
f_pciaddr="$xd{0,4}:{0,1}$xd{2}:$xd{2}\.$xd"
re_nfp_vf='^NFP . VF.\..+ '"$f_pciaddr"'$'
re_pciaddr='^'"$f_pciaddr"'$'
########################################################################
declare -A if_db_ifname
declare -A if_db_driver
declare -A if_db_desc
if_db_list=()
########################################################################
##  List interfaces with their driver and bus-info

for ifname in $list ; do
    if [ "$ifname" == "lo" ]; then
        continue
    fi
    info=$(ethtool -i $ifname 2> /dev/null \
        | tr '\n' '@')
    driver=$(echo $info \
        | sed -rn 's/^.*driver:\s*(\S+)@.*$/\1/p')
    businfo=$(echo $info \
        | sed -rn 's/^.*@bus-info: ([^@]*)@.*$/\1/p')
    if [[ "$businfo" =~ $re_nfp_vf ]]; then
        idx=$(echo $businfo \
            | sed -rn 's/^.*\sVF.\.([0-9]+)\s.*$/\1/p')
        pciaddr=$(echo $businfo \
            | sed -rn 's/^.*\s(\S+)$/\1/p')

        printf -v s_ifname "d-vf-%02u" $idx
        printf -v desc "VF %2u REPR (%s)" $idx "$pciaddr"
    elif [[ "$businfo" =~ $re_pciaddr ]]; then
        printf -v s_ifname "e-pci-%s" $businfo
        printf -v desc "PCI %s" "$businfo"
    else
        s_ifname="a-other"
        desc=""
        ppfile="/sys/class/net/$ifname/phys_port_name"
        if [ -f $ppfile ]; then
            phys_port=$(cat $ppfile 2> /dev/null)
            re_p='^p[0-9]+$'
            re_pf='^pf[0-9]+$'
            re_vf='^pf[0-9]+vf[0-9]+$'
            if [[ "$phys_port" =~ $re_p ]]; then
                idx=${phys_port#p}
                printf -v s_ifname "b-p-%02u" $idx
                printf -v desc "P  %2u" $idx
            elif [[ "$phys_port" =~ $re_pf ]]; then
                idx=${phys_port#pf}
                printf -v s_ifname "c-pf-%02u" $idx
                printf -v desc "PF %2u" $idx
            elif [[ "$phys_port" =~ $re_vf ]]; then
                idx=${phys_port#*vf}
                printf -v s_ifname "d-vf-%02u" $idx
                printf -v desc "VF %2u REPR" $idx
            fi
        fi
    fi
    s_ifname="$s_ifname-$ifname"
    if_db_ifname[$s_ifname]="$ifname"
    if_db_driver[$s_ifname]="$driver"
    if_db_desc[$s_ifname]="$desc"
    if_db_list+=( "$s_ifname" )
done

########################################################################

s_if_list=$(echo ${if_db_list[@]} \
    | tr ' ' '\n' \
    | sort \
    | tr '\n' ' ')

########################################################################

for s_ifname in $s_if_list ; do
    printf "  %-16s %-14s %s\n" \
        "${if_db_ifname[$s_ifname]}" \
        "${if_db_driver[$s_ifname]}" \
        "${if_db_desc[$s_ifname]}" \

done

########################################################################

exit 0
