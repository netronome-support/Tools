#!/bin/bash

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
        *)
            vmlist+=( "$arg" )
            ;;
        esac
    else
        case "$param" in
        "state") VIRSH_WAIT_FOR_STATE="$arg" ;;
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
    echo -n "Wait for VM(s) "
fi

idx=0
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
        idx=$(( idx + 1 ))
        if [ $idx -gt $VIRSH_WAIT_FOR_TIMEOUT ]; then
            echo " ERROR"
            exit -1
        fi
    done
done

if [ "$optQuiet" == "" ]; then
    case "$VIRSH_WAIT_FOR_STATE" in
      'running') msg="UP" ;;
      'shut off') msg="DOWN" ;;
      *) msg="" ;;
    esac
    echo " $msg"
fi

########################################################################
exit 0
