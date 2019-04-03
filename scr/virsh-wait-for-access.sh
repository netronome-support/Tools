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
which virsh-get-vm-ipaddr.sh > /dev/null 2>&1
    check_status "'virsh-get-vm-ipaddr.sh' is not installed"
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
sshopts+=()
sshopts+=( "-q" )
sshopts+=( "-o" "StrictHostKeyChecking=no" )
sshopts+=( "-o" "UserKnownHostsFile=/dev/null" )
sshopts+=( "-o" "ConnectionAttempts=30" )
sshopts+=( "-o" "ServerAliveInterval=300" )
if [ "$VIRSH_ACCESS_SSH_USERNAME" != "" ]; then
    sshopts+=( "-l" "$VIRSH_ACCESS_SSH_USERNAME" )
fi
if [ "$VIRSH_ACCESS_SSH_PRIVATE_KEY_FILE" != "" ]; then
    sshopts+=( "-i" "$VIRSH_ACCESS_SSH_PRIVATE_KEY_FILE" )
fi
########################################################################
if [ "$optQuiet" == "" ]; then
    echo -n "Wait for VM access "
fi

idx=0
for vmname in ${vmlist[@]} ; do
    while : ; do
        if [ $idx -gt 0 ]; then
            sleep 1
            if [ "$optQuiet" == "" ]; then
                echo -n '.'
            fi
        fi
        idx=$(( idx + 1 ))
        if [ $idx -gt $VIRSH_WAIT_FOR_TIMEOUT ]; then
            echo " ERROR"
            exit -1
        fi
        ipaddr=$(virsh-get-vm-ipaddr.sh $vmname)
        if [ $? -ne 0 ]; then
            continue
        fi
        ping -q -c 1 -W 1 "$ipaddr" > /dev/null
        if [ $? -ne 0 ]; then
            continue
        fi
        ssh ${sshopts[@]} $ipaddr true
        if [ $? -eq 0 ]; then
            break
        fi
    done
done

if [ "$optQuiet" == "" ]; then
    echo " SUCCESS"
fi

########################################################################
exit 0
