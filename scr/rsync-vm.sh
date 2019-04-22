#!/bin/bash

########################################
# Command Line Parsing

param=""
arglist=()
vm_name_list=()
ropts=()

for arg in "$@" ; do
    if [ "$param" == "" ]; then
        case "$arg" in
          "--help"|"-h")
            echo "Update VM(s) via rsync"
            echo "  --help -h"
            echo "  --verbose -v"
            echo "  --vm-name-filter"
            echo "  --vm-name"
            echo "  --user-name"
            echo "  --target"
            echo "  --ssh-key-file"
            exit
            ;;
          "--verbose"|"-v")     optVerbose="yes"
                                ropts+=( "--verbose" ) ;;
          "--vm-name-filter")   param="$arg" ;;
          "--vm-name")          param="$arg" ;;
          "--user-name")        param="$arg" ;;
          "--target")           param="$arg" ;;
          "-R"|"--relative")    ropts+=( "$arg" ) ;;
          "--ssh-key-file")     param="$arg" ;;
          "--network-type")     param="$arg" ;;
          "--network-name")     param="$arg" ;;
          "--bridge-name")      param="$arg" ;;
          *)
            if [ ${#vm_name_list[@]} -eq 0 ] \
                && [ "$vm_name_filter" == "" ]; then
                vm_name_list+=( "$arg" )
            else
                arglist+=( "$arg" )
            fi
            ;;
        esac
    else
        case "$param" in
          "--vm-name-filter")   vm_name_filter="$arg" ;;
          "--vm-name")          vm_name_list+=( "$arg" ) ;;
          "--user-name")        SSH_USERNAME="$arg" ;;
          "--target")           RSYNC_TARGET="$arg" ;;
          "--ssh-key-file")     SSH_PRIVATE_KEY_FILE="$arg" ;;
          "--network-type")     export VIRSH_IFACE_NETWORK_TYPE="$arg" ;;
          "--network-name")     export VIRSH_IFACE_NETWORK_NAME="$arg" ;;
          "--bridge-name")      export VIRSH_IFACE_BRIDGE_NAME="$arg" ;;
        esac
        param=""
    fi
done

########################################
function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}
########################################
# Any command in a pipeline must trigger an error:
set -o pipefail
########################################
tlist=()
tlist+=( virsh ssh rsync )
tlist+=( virsh-get-vm-ipaddr.sh )
for tool in ${tlist[@]} ; do
    which $tool > /dev/null 2>&1
        check_status "required tool '$tool' is missing"
done
########################################
sshopts+=()
sshopts+=( "-q" )
sshopts+=( "-o" "StrictHostKeyChecking=no" )
sshopts+=( "-o" "UserKnownHostsFile=/dev/null" )
sshopts+=( "-o" "ConnectionAttempts=300" )
sshopts+=( "-o" "ServerAliveInterval=300" )
if [ "$SSH_PRIVATE_KEY_FILE" != "" ]; then
    if [ -f $SSH_PRIVATE_KEY_FILE ]; then
        sshopts+=( "-i" "$SSH_PRIVATE_KEY_FILE" )
    fi
fi
sshopts+=( "-l" "${SSH_USERNAME-"root"}" )
sshcmd="ssh ${sshopts[@]}"
########################################
ropts+=( "" )
ropts+=( "--recursive" )
ropts+=( "--copy-links" )
ropts+=( "--update" )
ropts+=( "--perms" )
ropts+=( "-e" "$sshcmd" )
########################################
##  Save 'virsh list  --state-running' into a list
mapfile -t vmlisting < \
   <( virsh list --state-running  \
    | tail -n +3 \
    | awk '{print $2 " " $3}' \
    )
########################################
##  Convert listing to variables
declare -A vm_state
vm_running_list=()
for line in "${vmlisting[@]}" ; do
    vmname=${line/ *}
    state=${line/* }
    if [ "$vmname" != "" ]; then
        vm_state[$vmname]="$state"
        vm_running_list+=( "$vmname" )
    fi
done
########################################
declare -A vm_access_flags
for vmname in ${vm_name_list[@]} ; do
    test "${vm_state[$vmname]}" == "running"
        check_status "$vmname is not running"
    vm_access_flags[$vmname]=ACCESS
done
########################################
if [ "$vm_name_filter" != "" ]; then
    for vmname in ${vm_running_list[@]} ; do
        echo "$vmname" \
            | grep -E "^$vm_name_filter" > /dev/null
        if [ $? -eq 0 ]; then
            vm_access_flags[$vmname]=ACCESS
        fi
    done
fi
########################################
declare -A vm_ip_addr
for vmname in ${vm_running_list[@]} ; do
    if [ "${vm_access_flags[$vmname]}" == "ACCESS" ]; then
        ipaddr=$(virsh-get-vm-ipaddr.sh $vmname)
            check_status "could not determine IP address for $vmname"
        vm_ip_addr[$vmname]="$ipaddr"
    fi
done
########################################
vm_access_list=()
for vmname in ${vm_running_list[@]} ; do
    if [ "${vm_access_flags[$vmname]}" == "ACCESS" ]; then
        vm_access_list+=( "$vmname" )
    fi
done
########################################
test ${#vm_access_list[@]} -gt 0
    check_status "no valid VM specified"
if [ ${#vm_access_list[@]} -eq 1 ]; then
    vmname=${vm_access_list[0]}
    ipaddr=${vm_ip_addr[$vmname]}
    exec rsync "${ropts[@]}" "${arglist[@]}" $ipaddr:$RSYNC_TARGET
else
    for vmname in ${vm_access_list[@]} ; do
        ipaddr=${vm_ip_addr[$vmname]}
        rsync "${ropts[@]}" "${arglist[@]}" $ipaddr:$RSYNC_TARGET
            check_status "rsync to VM '$vmname' ($ipaddr) failed"
    done
fi
########################################
exit 0
