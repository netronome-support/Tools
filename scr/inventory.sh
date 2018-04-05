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
if [ -f /etc/os-release ]; then
    . /etc/os-release
    show "OS" "$NAME $VERSION"
fi

########################################################################
show "Kernel" "$(uname -r)"

########################################################################
manu=$(dmidecode --type system | sed -rn 's/^\s*Manufacturer: (.*)$/\1/p')
prod=$(dmidecode --type system | sed -rn 's/^\s*Product Name: (.*)$/\1/p')

show "Server" "$manu $prod"

########################################################################
vendor=$(dmidecode --type bios   | sed -rn 's/^\s*Vendor: (.*)$/\1/p')
version=$(dmidecode --type bios  | sed -rn 's/^\s*Version: (.*)$/\1/p')
rel_date=$(dmidecode --type bios | sed -rn 's/^\s*Release Date: (.*)$/\1/p')
revision=$(dmidecode --type bios | sed -rn 's/^\s*BIOS Revision: (.*)$/\1/p')

show "BIOS" "$vendor Version $version ($rel_date); Revision $revision"

########################################################################
cpu=$(lscpu | sed -rn 's/^Vendor ID:\s+(\S.*)$/\1/p')
cpu_model=$(lscpu | sed -rn 's/^Model name:\s+(\S.*)$/\1/p')
if [ "$cpu_model" == "" ]; then
  cpu_version=$(dmidecode --type processor \
    | sed -rn 's/^\s*Version: (.*)$/\1/p' \
    | head -1)
  cpu="$cpu $cpu_version"
else
  cpu="$cpu $cpu_model"
fi
cpu_freq=$(lscpu | sed -rn 's/^CPU MHz:\s+(\S.*)$/\1/p')
[ "$cpu_freq" != "" ] && cpu="$cpu ${cpu_freq}MHz"

show "CPU" "$cpu"

########################################################################
cps=$(lscpu | sed -rn 's/^Core.*per socket:\s+(\S.*)$/\1/p')
scn=$(lscpu | sed -rn 's/^Socket.*:\s+(\S.*)$/\1/p')

show "NUMA" "$scn sockets, $cps cores/socket"

########################################################################
mem=$(cat /proc/meminfo | sed -rn 's/^MemTotal:\s+(\S.*)$/\1/p')
show "Memory" "$mem"

########################################################################
function extract () {
    local varname="$1"
    local field="$2"
    local value=$(echo "$line" \
        | sed -rn 's/^.*@@@'"$field"':\s*([^@]+)@@@.*$/\1/p')
    printf -v $varname "%s" "$value"
}

dmidecode --type memory \
    | awk '{printf "%s@@@", $0}' \
    | sed -r 's/@@@@@@/@@@\n@@@/g' \
    | sed -r 's/@@@\s*/@@@/g' \
    | grep -E "^@@@Handle" \
    | grep -E "@@@Memory Device@@@" \
    | grep -E "@@@Form Factor: DIMM@@@" \
    | grep -E "@@@Data Width: [0-9]+ bits@@@" \
    | while read line ;
do
    #extract "m_width_t"     "Total Width"
    extract "m_width_d"     "Data Width"
    extract "m_size"        "Size"
    extract "m_locator"     "Locator"
    #extract "m_manu"        "Manufacturer"
    extract "m_type"        "Type"
    extract "m_speed"       "Speed"
    extract "m_rank"        "Rank"
    #extract "m_part_n"      "Part Number"
    extract "m_cfg_clock"   "Configured Clock Speed"
    extract "m_max_clock"    "Configured Voltage"
    info="$m_width_d, $m_size, $m_locator"
    info="$info, $m_cfg_clock (max $m_speed), rank $m_rank"
    show "DIMM" "$info"
done

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
    show "NFP" "MISSING!!"
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
virsh="$(which virsh 2> /dev/null)"
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
