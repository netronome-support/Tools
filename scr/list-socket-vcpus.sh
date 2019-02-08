#!/bin/bash

########################################################################

function usage () {
cat <<EOT

$(basename $0) - List vCPUs on a specific NUMA socket
  - Only list the first vCPU of each Core

  -h --help         Print this help
  --socket <int>    Specify NUMA socket
  --skip <int>      Skip the first core(s)
  --count <int>     Don not list more vCPUs than this number
  --delim <text>    Delimit the output with this text

EOT
}

########################################################################
##  Default values

: ${socket:=0}
: ${skip:=0}
: ${delim:=" "}

########################################################################

param=""
opt_update=""
opt_dryrun=""

for arg in $@ ; do
    if [ "$param" == "" ]; then
        case $arg in
        "-h"|"--help")
            usage
            exit 0
            ;;
        "--socket"|"--node") param="socket" ;;
        "--skip") param="skip" ;;
        "--count") param="count" ;;
        "--delim") param="delim" ;;
        *)
            echo "ERROR: unknown argument: $arg"
            exit -1
            ;;
        esac
    else
        case "$param" in
        "socket") socket="$arg" ;;
        "skip") skip="$arg" ;;
        "count") count="$arg" ;;
        "delim") delim="$arg" ;;
        esac
        param=""
    fi
done

########################################################################
##  CPU,Core,Socket,Node,,L1d,L1i,L2,L3
mapfile -t cpulist < \
  <( lscpu --parse \
   | grep -vE '^#' \
   )
########################################################################
declare -A cores

dlim=""
for item in "${cpulist[@]}" ; do
    vcpu=$(echo "$item" | cut -d ',' -f 1)
    core=$(echo "$item" | cut -d ',' -f 2)
    sock=$(echo "$item" | cut -d ',' -f 3)
    if [ $sock -ne $socket ]; then
        continue
    fi
    if [ "${cores[$core]}" == "" ]; then
        cores[$core]="$vcpu"
        if [ $skip -gt 0 ]; then
            skip=$(( skip - 1 ))
            continue
        fi
        printf "%s%s" "$dlim" "$vcpu"
        dlim="$delim"
        count=$(( count - 1 ))
        if [ $count -eq 0 ]; then
            break
        fi
    fi
done
printf "\n"

########################################################################
exit 0
