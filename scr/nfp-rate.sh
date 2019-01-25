#!/bin/bash

args=()
args+=( "--count" ) # Show Packet Counters
#args+=( "--norm" ) # Show Normalized Rates
args+=( "--list-drop" )
args+=( "--pktsize" ) # Show Average Packet Size (APS)
args+=( "--reset" )
args+=( "--ignore-zero" )
args+=( "-i" "1" ) # Sample Interval

########################################################
nfp_if_list=()
########################################################
if [ -d /sys/bus/pci/drivers/nfp ]; then
    nfplist=$(find /sys/bus/pci/drivers/nfp -type l -name '*:*:*.*')
    for nfpdir in $nfplist ; do
        nfp_if_list+=( $(ls $nfpdir/net \
            | grep -v -E '^nfp_v') )
    done
fi
########################################################
nfp_if_list+=( $(cat /proc/net/dev \
    | sed -rn 's/^\s*(nfp_p[0-9]+):.*$/\1/p' \
    | sort) )
########################################################
nfp_if_list+=( $(cat /proc/net/dev \
    | sed -rn 's/^\s*(sdn_p[0-9]+):.*$/\1/p' \
    | sort) )
########################################################

if [ ${#nfp_if_list[@]} -gt 0 ]; then
    args+=( "--total-start" )
    args+=( ${nfp_if_list[@]} )
    args+=( "--total" )
fi
########################################################
nfp_if_list=( $(cat /proc/net/dev \
    | sed -rn 's/^\s*(sdn_pkt):.*$/\1/p' \
    | sort) )
if [ ${#nfp_if_list[@]} -gt 0 ]; then
    args+=( ${nfp_if_list[@]} )
fi
########################################################
nfp_if_list=($(cat /proc/net/dev \
  | sed -rn 's/^\s*(nfp_v.*):.*$/\1/p' \
  | sort -V) )

if [ ${#nfp_if_list[@]} -gt 0 ]; then
    args+=( "--total-start" )
    args+=( ${nfp_if_list[@]} )
    args+=( "--total" )
fi
########################################################
exec rate ${args[@]} $@
