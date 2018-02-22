#!/bin/bash

########################################################################
if [ "$INV_PRINT_MODE" == "CSV" ]; then
    # Useful for including the output into a Spreadsheet
    function show () {
        local field="$1"
        local value="$2"
        printf "\"%s\",\"%s\"\n" "$field" "$value"
    }
else
    function show () {
        local field="$1"
        local value="$2"
        printf "%-14s %s\n" "$field" "$value"
    }
fi

########################################################################
show "Hostname" "$(hostname)"

########################################################################
. /etc/os-release || exit -1
show "OS" "$NAME $VERSION"

########################################################################
show "Kernel" "$(uname -r)"

########################################################################
manu=$(dmidecode --type system | sed -rn 's/^\s*Manufacturer: (.*)$/\1/p')
prod=$(dmidecode --type system | sed -rn 's/^\s*Product Name: (.*)$/\1/p')

show "Server" "$manu $prod"

########################################################################
cpu=$(lscpu | sed -rn 's/^Vendor ID:\s+(\S.*)$/\1/p')
cpu_model=$(lscpu | sed -rn 's/^Model name:\s+(\S.*)$/\1/p')
[ "$cpu_model" != "" ] && cpu="$cpu $cpu_model"
cpu_freq=$(lscpu | sed -rn 's/^CPU MHz:\s+(\S.*)$/\1/p')
[ "$cpu_freq" != "" ] && cpu="$cpu ${cpu_freq}MHz"
cps=$(lscpu | sed -rn 's/^Core.*per socket:\s+(\S.*)$/\1/p')
scn=$(lscpu | sed -rn 's/^Socket.*:\s+(\S.*)$/\1/p')

show "CPU" \
  "$cpu ($scn sockets, $cps cores/socket)"

########################################################################
mem=$(cat /proc/meminfo | sed -rn 's/^MemTotal:\s+(\S.*)$/\1/p')
show "Memory" "$mem"

########################################################################
ovsctl="/opt/netronome/bin/ovs-ctl"
if [ -x "$ovsctl" ]; then
  agvers=$($ovsctl version | sed -rn 's/^Netro.*version //p')
  show "Agilio" "$agvers"
fi

########################################################################
hwinfo="/opt/netronome/bin/nfp-hwinfo"
nfp_present="unknown"
if [ -x $hwinfo ]; then
  fn="/tmp/nfp-hwinfo.txt"
  $hwinfo > $fn 2> /dev/null
  if [ $? -ne 0 ]; then
    printf "%-10s %s\n" "NFP" "MISSING!!"
    nfp_present="missing"
  else
    nfp_present="yes"
    model=$(  sed -rn 's/^assembly.model=(.*)$/\1/p' $fn)
    partno=$( sed -rn 's/^assembly.partno=(.*)$/\1/p' $fn)
    rev=$(    sed -rn 's/^assembly.revision=(.*)$/\1/p' $fn)
    sn=$(     sed -rn 's/^assembly.serial=(.*)$/\1/p' $fn)
    bsp=$(    sed -rn 's/^board.setup.version=(.*)$/\1/p' $fn)
    freq=$(   sed -rn 's/^core.speed=(.*)$/\1/p' $fn)
    show "NFP" \
      "$model ($partno rev=$rev sn=$sn ${freq}MHz)"
    show "BSP" "$bsp"
  fi
fi

########################################################################
if [ -x /opt/netronome/bin/nfp-media ] && [ "$nfp_present" == "yes" ]; then
  phymode=$(/opt/netronome/bin/nfp-media \
    | tr '\n' ' ' \
    | sed -r 's/\s+\(\S+\)\s*/ /g')
  show "Media" "$phymode"
fi

########################################################################
lscpu \
  | sed -rn 's/^NUMA\snode([0-9]).*:\s+(\S+)$/\1:\2/p' \
  | while read line ; do
      cpuidx=${line/:*/}
      vcpulist=${line/*:/}
      show "NUMA $cpuidx" "$vcpulist"
    done

########################################################################
nfpsys="/sys/bus/pci/drivers/nfp"
nfpnuma="UNKNOWN"
nfpbdf="UNKNOWN"
if [ -d "$nfpsys" ]; then
  nfpbdf=$(find $nfpsys -name '00*' \
    | sed -r 's#^.*/##' \
    | head -1)
  if [ -h "$nfpsys/$nfpbdf" ]; then
    nfpnuma="$(cat $nfpsys/$nfpbdf/numa_node)"
  fi
  show "NFP NUMA" "$nfpnuma"
  show "NFP BDF"  "$nfpbdf"
fi

########################################################################
show "Kernel Command Line" ""
show "" "$(cat /proc/cmdline)"

########################################################################
viopid=$(pgrep virtiorelayd)
if [ "$viopid" != "" ]; then
  show "VirtIO Relay Daemon Command Line" ""
  show "" "$(cat /proc/$viopid/cmdline | tr '\0' ' ')"
fi

########################################################################
virsh="$(which virsh)"
if [ "$virsh" != "" ]; then
  show "VM CPU Usage" ""
  for inst in $(virsh list --name) ; do
    if [ "$inst" != "" ]; then
      vcpulist=$($virsh vcpuinfo $inst \
        | sed -rn 's/^CPU:\s+(\S+)$/\1/p' \
        | tr '\n' ',' \
        | sed -r 's/,$/\n/' )
      show "$inst" "$vcpulist"
    fi
  done
fi

########################################################################
exit 0
