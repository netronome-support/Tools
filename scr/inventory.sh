#!/bin/bash

########################################################################
# This script is maintained at:
#   https://github.com/netronome-support/Tools
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
tmpdir=$(mktemp --directory)
########################################################################
cat <<EOF > $tmpdir/nfp_dev_types.list
AMDA0081-0001 @@ ISA-4000-40-1-2 @@ Hydrogen @@ 1 x 40 GbE
AMDA0096-0001 @@ ISA-4000-10-2-2 @@ Lithium @@ 2 x 10 GbE
AMDA0097-0001 @@ ISA-4000-40-2-2 @@ Beryllium @@ 2 x 40 GbE
AMDA0099-0001 @@ ISA-4000-25-2-2 @@ Carbon @@ 2 x 25 GbE
AMDA0096-0001 @@ ISA-FX @@ Agilio-FX @ -
EOF
types_fmt='^(.*) @@ (.*) @@ (.*) @@ (.*)$'
########################################################################
if [ -f /etc/os-release ]; then
    . /etc/os-release
    show "OS" "$NAME $VERSION"
fi

########################################################################
show "Kernel" "$(uname -r)"

########################################################################
if [ -x "$(which dmidecode 2> /dev/null)" ]; then
    system="$tmpdir/dmidecode-system.txt"
    dmidecode --type system > $system
    manu=$(cat $system | sed -rn 's/^\s*Manufacturer: (.*)$/\1/p')
    prod=$(cat $system | sed -rn 's/^\s*Product Name: (.*)$/\1/p')

    show "Server" "$manu $prod"

    bios="$tmpdir/dmidecode-bios.txt"
    dmidecode --type bios > $bios
    vendor=$(  cat $bios | sed -rn 's/^\s*Vendor: (.*)$/\1/p')
    version=$( cat $bios | sed -rn 's/^\s*Version: (.*)$/\1/p')
    rel_date=$(cat $bios | sed -rn 's/^\s*Release Date: (.*)$/\1/p')
    revision=$(cat $bios | sed -rn 's/^\s*BIOS Revision: (.*)$/\1/p')

    show "BIOS" "$vendor Version $version ($rel_date); Revision $revision"
fi

########################################################################
cpu=$(lscpu | sed -rn 's/^Vendor ID:\s+(\S.*)$/\1/p')
cpu_model=$(lscpu | sed -rn 's/^Model name:\s+(\S.*)$/\1/p')
if [ "$cpu_model" == "" ] && [ -x "$(which dmidecode 2> /dev/null)" ]; then
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
if [ "$mem" != "" ]; then
    value=$(echo $mem | cut -d ' ' -f 1)
    unit=$( echo $mem | cut -d ' ' -f 2)
    case "$unit" in
        "kB") value=$(( value / 1024 )) ; unit="MB" ;;
    esac
    show "Memory" "$value $unit"
fi

########################################################################
function extract () {
    local varname="$1"
    local field="$2"
    local value=$(echo "$line" \
        | sed -rn 's/^.*@@@'"$field"':\s*([^@]+)@@@.*$/\1/p')
    printf -v $varname "%s" "$value"
}

if [ -x "$(which dmidecode 2> /dev/null)" ]; then
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
fi

########################################################################
ovsctl="/opt/netronome/bin/ovs-ctl"
if [ -x "$ovsctl" ]; then
    agvers=$($ovsctl version | sed -rn 's/^Netro.*version //p')
    show "Agilio" "$agvers"
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
nfp_pci_list=( $(lspci -d 19ee: -s '00.0' \
    | cut -d ' ' -f 1 ) )
########################################################################
dmesg | grep ' nfp 0000' > $tmpdir/dmesg.log
########################################################################
hwinfo="/opt/netronome/bin/nfp-hwinfo"
nfpmedia="/opt/netronome/bin/nfp-media"
nfpsys="/sys/bus/pci/drivers/nfp"
########################################################################
nfpidx=0
for nfp in ${nfp_pci_list[@]} ; do
    ####################################################################
    show "NFP" "$nfp"
    nfp_present="unknown"
    if [ -x $hwinfo ]; then
        fn="$tmpdir/nfp-hwinfo-$nfp.txt"
        $hwinfo -n $nfpidx > $fn 2> /dev/null
        if [ $? -eq 0 ]; then
            nfp_present="yes"
            desc=""
            model=$(  sed -rn 's/^assembly.model=(.*)$/\1/p' $fn)
            partno=$( sed -rn 's/^assembly.partno=(.*)$/\1/p' $fn)
            rev=$(    sed -rn 's/^assembly.revision=(.*)$/\1/p' $fn)
            sn=$(     sed -rn 's/^assembly.serial=(.*)$/\1/p' $fn)
            bsp=$(    sed -rn 's/^board.setup.version=(.*)$/\1/p' $fn)
            freq=$(   sed -rn 's/^core.speed=(.*)$/\1/p' $fn)
            # Part Database info
            line=$(grep -E "^$partno @@ " $tmpdir/nfp_dev_types.list \
                | head -1)
            prodnum=$(echo "$line" | sed -rn "s/$types_fmt/\2/p")
            prtdesc=$(echo "$line" | sed -rn "s/$types_fmt/\4/p")
            test "$partno"  != "" && desc="${desc}$partno"
            test "$rev"     != "" && desc="${desc} rev=$rev"
            test "$sn"      != "" && desc="${desc} sn=$sn"
            test "$freq"    != "" && desc="${desc} ${freq}MHz"
            test "$prtdesc" != "" && desc="${desc} '$prtdesc'"
            show "  LINE" "$line"
            show "  HWINFO" "$model ($desc)"
            show "  BSP" "$bsp"
        fi
    fi

    assembly=$(cat $tmpdir/dmesg.log \
        | sed -rn 's#^.* nfp 0000:'$nfp': ##p' \
        | sed -rn 's#^Assembly: (\S+) .*$#\1#p')
    if [ "$assembly" != "" ]; then
        show "  Assembly" "$assembly"
    fi

    ####################################################################
    if [ -x $nfpmedia ]; then
        nfpmedia -n $nfpidx > $tmpdir/nfp-media-$nfpidx.txt 2> /dev/null
        if [ $? -eq 0 ]; then
            phymode=$(cat $tmpdir/nfp-media-$nfpidx.txt \
                | tr '\n' ' ' \
                | sed -r 's/\s+\(\S+\)\s*/ /g')
            show "  Media" "$phymode"
        fi
    fi

    ####################################################################
    nfpnuma="UNKNOWN"
    nfpbdf="UNKNOWN"
    if [ -d "$nfpsys" ]; then
        symlink="$nfpsys/0000:$nfp"
        if [ -h "$symlink" ]; then
            nfpnuma="$(cat $symlink/numa_node)"
        fi
        show "  NUMA" "$nfpnuma"
    fi

    ####################################################################
    nfpidx=$(( nfpidx + 1 ))
done
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
    vm_name_list=( $(virsh list --name) )
    if [ ${#vm_name_list[@]} -gt 0 ]; then
        show "VM List" ""
    fi
    for inst in ${vm_name_list[@]} ; do
        vcpulist=$($virsh vcpuinfo $inst \
            | sed -rn 's/^CPU:\s+(\S+)$/\1/p' \
            | tr '\n' ',' \
            | sed -r 's/,$/\n/' )
        show "  $inst" "$vcpulist"
    done
fi

########################################################################
rm -rf $tmpdir
########################################################################
exit 0
