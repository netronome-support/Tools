#!/bin/bash

########################################################################
# This script is maintained at:
#   https://github.com/netronome-support/Tools
########################################################################
: ${VIRSH_WAIT_FOR_STATE:='running'}
: ${VIRSH_WAIT_FOR_TIMEOUT:=60}
########################################################################
function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}
########################################################################
which virsh > /dev/null 2>&1
    check_status "'virsh' is not installed"
########################################################################
param=""
for arg in "$@" ; do
    if [ "$param" == "" ]; then
        case $arg in
        "-h"|"--help")
            echo "USAGE: $(basename $0) [--state <state>] <vm list>"
            exit 0
            ;;
        "--state") param="state" ;;
        "--quiet"|"-q") optQuiet=yes ;;
        "--no-timeout") VIRSH_WAIT_FOR_TIMEOUT="" ;;
        "--timeout") param="timeout" ;;
        *)
            vmlist+=( "$arg" )
            ;;
        esac
    else
        case "$param" in
        "state") VIRSH_WAIT_FOR_STATE="$arg" ;;
        "timeout") VIRSH_WAIT_FOR_TIMEOUT="$arg" ;;
        esac
        param=""
    fi
done
########################################################################
test ${#vmlist[@]} -gt 0
    check_status "no VMs specified"
########################################################################
for vmname in ${vmlist[@]} ; do
    virsh dominfo $vmname > /dev/null 2>&1
        check_status "VM '$vmname' does not exist"
done
########################################################################
if [ "$optQuiet" == "" ]; then
    echo -n "Wait for state '$VIRSH_WAIT_FOR_STATE' ..."
fi

tm_start=$(date +'%s')
for vmname in ${vmlist[@]} ; do
    while : ; do
        state=$(virsh dominfo $vmname \
            | sed -rn 's/^State:\s*(\S.*)$/\1/p')
        if [ "$state" == "$VIRSH_WAIT_FOR_STATE" ]; then
            break
        fi
        if [ "$optQuiet" == "" ]; then
            echo -n '.'
        fi
        sleep 1
        if [ "$VIRSH_WAIT_FOR_TIMEOUT" != "" ]; then
            tm_now=$(date +'%s')
            tm_limit=$(( tm_start + $VIRSH_WAIT_FOR_TIMEOUT ))
            if [ $tm_now -gt $tm_limit ]; then
                if [ "$optQuiet" == "" ]; then
                    echo " ERROR"
                else
                    false ; check_status \
                        "VM '$vmname' did not reach state '$VIRSH_WAIT_FOR_STATE'"
                fi
                exit -1
            fi
        fi
    done
done

if [ "$optQuiet" == "" ]; then
    case "$VIRSH_WAIT_FOR_STATE" in
      'running')    msg="UP" ;;
      'shut off')   msg="DOWN" ;;
      'paused')     msg="PAUSED" ;;
      *) msg="" ;;
    esac
    echo " $msg"
fi

########################################################################
exit 0
