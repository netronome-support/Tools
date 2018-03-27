#!/bin/bash

# This script builds and runs the peak-rate-monitor DPDK application.
#
# The script assumes DPDK variables to be specified in /etc/dpdk.conf

if [ ! -f /etc/dpdk.conf ]; then
    echo "ERROR: missing /etc/dpdk.conf"
    exit -1
fi

. /etc/dpdk.conf

export RTE_OUTPUT="$HOME/.cache/dpdk/prm"
mkdir -p $RTE_OUTPUT

make -C . install \
    || exit -1

echo 128 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Hardcoded Core and Port masks:
printf -v coremask "0x%04x" 7
printf -v portmask "0x%04x" 3

cmd=( "$RTE_OUTPUT/peak-rate-monitor" )
cmd+=( "-c" "$coremask" )
cmd+=( "-n" "2" )
cmd+=( "-m" "128" )
cmd+=( "--file-prefix" "prm_" )
cmd+=( "--" )
cmd+=( "-T" "1" )
cmd+=( "-p" "$portmask" )

# -m <port index>:<measurement window [ms]>:<dampening factor>
cmd+=( "-m" "0:100:0.95" )
cmd+=( "-m" "0:10:0.95" )
cmd+=( "-m" "0:1:0.95" )
cmd+=( "-m" "0:0.1:0.95" )
cmd+=( "-m" "0:0.01:0.95" )

# Save date and command line into logfile
logfile="/var/log/dpdk-peak-rate-monitor.log"
cat << EOF | tee -a $logfile
--------------------------------
Date: $(date)
Command:  ${cmd[@]}
--
EOF

# Execute application
${cmd[@]} 2>&1 | tee -a $logfile
