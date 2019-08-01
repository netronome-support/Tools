#!/bin/bash

########################################################################
# This script is maintained at:
#   https://github.com/netronome-support/Tools
########################################################################
##  Install 'ethtool' if it is missing

install-packages.sh "ethtool" "bc" \
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
declare -A if_db_type
declare -A if_db_index
declare -A if_db_addr
if_db_list=()
########################################################################
function usage () {
cat <<EOF
$(basename $0) - list netdev interfaces with selected meta data
Syntax: $(basename $0) [<options>]
Options:
  -h|--help             - Print this help information
  -d|--driver <name>    - Only list netdevs with specified driver
  -t|--type <type>      - Only list netdevs with specified type
  -i|--index <index>    - Only list netdevs with specified index
  -a|--addr <address>   - Only list netdevs with specified address
  -b|--brief            - Only list netdev names
EOF
}
########################################################################
param=""
opt_driver=""
opt_format=""

for arg in $@ ; do
    if [ "$param" == "" ]; then
        case $arg in
        "-h"|"--help")
            usage
            exit 0
            ;;
        "-d"|"--driver") param="driver" ;;
        "-t"|"--type") param="type" ;;
        "-i"|"--index") param="index" ;;
        "-a"|"--addr") param="addr" ;;
        "-b"|"--brief") opt_format="brief" ;;
        *)
            echo "ERROR($(basename $0)): syntax error at '$arg'"
            exit -1
            ;;
        esac
    else
        case "$param" in
        "driver")   opt_driver="$arg" ;;
        "type")     opt_type="$arg" ;;
        "index")    opt_index="$arg" ;;
        "addr")     opt_addr="$arg" ;;
        esac
        param=""
    fi
done

########################################################################
##  List interfaces with their driver and bus-info

for ifname in $list ; do
    index="" ; addr=""
    if [ "$ifname" == "lo" ]; then
        continue
    fi
    info=$(ethtool -i $ifname 2> /dev/null \
        | tr '\n' '@')
    driver=$(echo $info \
        | sed -rn 's/^.*driver:\s*(\S+)@.*$/\1/p')
    businfo=$(echo $info \
        | sed -rn 's/^.*@bus-info: ([^@]*)@.*$/\1/p')
    pciaddr=$(echo " $businfo " \
        | sed -rn 's/^.*\s('$f_pciaddr')\s.*$/\1/p')
    addr="$pciaddr"
    s_ifname="a-other"
    ppfile="/sys/class/net/$ifname/phys_port_name"
    type=""
    if [ "$opt_driver" != "" ] && [ "$opt_driver" != "$driver" ]; then
        continue
    fi
    if [[ "$businfo" =~ $re_nfp_vf ]]; then
        index=$(echo $businfo \
            | sed -rn 's/^.*\sVF.\.([0-9]+)\s.*$/\1/p')
        pciaddr=$(echo $businfo \
            | sed -rn 's/^.*\s(\S+)$/\1/p')

        printf -v s_ifname "d-vf-%02u" $index
        type="VF-R"
        printf -v addr "%s" "$pciaddr"
    elif [ -f $ppfile ]; then
        phys_port=$(cat $ppfile 2> /dev/null)
        re_p='^p[0-9]+$'
        re_pf='^pf[0-9]+$'
        re_vf='^pf[0-9]+vf[0-9]+$'
        if [[ "$phys_port" =~ $re_p ]]; then
            index=${phys_port#p}
            printf -v s_ifname "b-p-%02u" $index
            type="P"
        elif [[ "$phys_port" =~ $re_pf ]]; then
            index=${phys_port#pf}
            printf -v s_ifname "c-pf-%02u" $index
            type="PF"
        elif [[ "$phys_port" =~ $re_vf ]]; then
            index=${phys_port#*vf}
            printf -v s_ifname "d-vf-%02u" $index
            type="VF-R"
        elif [ "$phys_port" == "" ]; then
            re_nfp_p_ifname='^nfp_p[0-9]$'
            if [[ "$ifname" =~ $re_nfp_p_ifname ]]; then
                index=${ifname#nfp_p}
                printf -v s_ifname "b-p-%02u" $index
                type="P"
            fi
        fi
    fi
    if [ "$type" == "" ] && [[ "$businfo" =~ $re_pciaddr ]]; then
        if [ "$driver" == "nfp_netvf" ]; then
            pci_addr=( $(echo $businfo \
                | tr ":." "\n" \
                | sed -r 's/^0+([0-9])$/\1/' ) \
            )
            busidx=$(( 16#${pci_addr[2]} ))
                
            if [ $busidx -ge 8 ]; then
                index=$(( 8 * ( $busidx - 8 ) + ${pci_addr[3]} ))
            fi
        fi
        printf -v s_ifname "e-pci-%s" $businfo
        type="PCI"
        addr="$businfo"
    fi
    if [ "$opt_type" != "" ] && [ "$opt_type" != "$type" ]; then
        continue
    fi
    if [ "$opt_index" != "" ] && [ "$opt_index" != "$index" ]; then
        continue
    fi
    if [ "$opt_addr" != "" ] && [ "$opt_addr" != "$addr" ]; then
        continue
    fi
    s_ifname="$s_ifname-$ifname"
    if_db_ifname[$s_ifname]="$ifname"
    if_db_driver[$s_ifname]="$driver"
    if_db_type[$s_ifname]="$type"
    if_db_index[$s_ifname]="$index"
    if_db_addr[$s_ifname]="$addr"
    if_db_list+=( "$s_ifname" )
done

########################################################################

s_if_list=$(echo ${if_db_list[@]} \
    | tr ' ' '\n' \
    | sort \
    | tr '\n' ' ')

########################################################################

for s_ifname in $s_if_list ; do
    case "$opt_format" in
      "brief")
        printf "%s\n" "${if_db_ifname[$s_ifname]}"
        ;;
      *)
        printf "  %-16s %-14s %-5s %2s %s\n" \
            "${if_db_ifname[$s_ifname]}" \
            "${if_db_driver[$s_ifname]}" \
            "${if_db_type[$s_ifname]}" \
            "${if_db_index[$s_ifname]}" \
            "${if_db_addr[$s_ifname]}"
    esac
done

########################################################################

exit 0
