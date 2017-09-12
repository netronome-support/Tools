#!/bin/bash

########################################################################
mkdir -p /mnt/huge
grep hugetlbfs /proc/mounts > /dev/null \
  || mount /mnt/huge

echo 128 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

########################################################################

cd $HOME/route

eal=()
# Cores (WARNING - more than one may cause issues)
eal+=("-c" "1" )
eal+=("-n" "2" )

arg=()
# Port Bitmask (in hexadecimal)
arg+=( "-p" "f" )
# Number of Queues per core
arg+=( "-q" "4" )

arg+=( "--iface-addr" "0:1#10.0.0.10/24" )
arg+=( "--iface-addr" "1:1#10.0.1.11/24" )
arg+=( "--iface-addr" "2:2#10.0.0.12/24" )
arg+=( "--iface-addr" "3:2#10.0.1.13/24" )

# Circular Route between routing domains
arg+=( "--route" "1#10.0.20.0/24@10.0.1.13" )
arg+=( "--route" "2#10.0.20.0/24@10.0.0.10" )
arg+=( "--route" "1#10.0.21.0/24@10.0.0.12" )
arg+=( "--route" "2#10.0.21.0/24@10.0.1.11" )

# Example routes toward external Next Hops
arg+=( "--route" "1#10.0.30.0/24@10.0.0.2" )
arg+=( "--route" "1#10.0.31.0/24@10.0.1.2" )
arg+=( "--route" "2#10.0.32.0/24@10.0.0.2" )
arg+=( "--route" "2#10.0.33.0/24@10.0.1.2" )

exec ./build/route ${eal[@]} -- ${arg[@]}
