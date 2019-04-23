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
checkPortList=()
for arg in "$@" ; do
    if [ "$param" == "" ]; then
        case $arg in
        "-h"|"--help")
            echo "USAGE: $(basename $0) [--state <state>] <vm list>"
            exit 0
            ;;
        "--state") param="state" ;;
        "--check-port") param="check-port" ;;
        "--check-ssh") optCheckSSH=yes ;;
        "--quiet"|"-q") optQuiet=yes ;;
        "--verbose"|"-v") optVerbose=yes ;;
        "--ping-only") optPingOnly=yes ;;
        "--skip-ping") optSkipPing=yes ;;
        "--no-timeout") VIRSH_WAIT_FOR_TIMEOUT="" ;;
        "--timeout") param="timeout" ;;
        *)
            vmlist+=( "$arg" )
            ;;
        esac
    else
        case "$param" in
        "state") VIRSH_WAIT_FOR_STATE="$arg" ;;
        "check-port") checkPortList+=( "$arg" ) ;;
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
function verbose () {
    local msg="$1"
    if [ "$optVerbose" != "" ]; then
        printf "DBG: %s\n" "$msg"
    fi
}
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
if [ "$VIRSH_ACCESS_SSH_PORT" != "" ]; then
    sshopts+=( "-p" "$VIRSH_ACCESS_SSH_PORT" )
fi
if [ "$VIRSH_ACCESS_SSH_PRIVATE_KEY_FILE" != "" ]; then
    sshopts+=( "-i" "$VIRSH_ACCESS_SSH_PRIVATE_KEY_FILE" )
fi
########################################################################
if [ "$optQuiet" == "" ] && [ "$optVerbose" == "" ]; then
    echo -n "Wait for VM access ..."
fi

verbose "checking access for VMs: ${vmlist[*]}"

idx=0
tm_start=$(date +'%s')
keep_trying=1
while [ $keep_trying -ne 0 ] ; do
    keep_trying=0
    for vmname in ${vmlist[@]} ; do
        if [ "$VIRSH_WAIT_FOR_TIMEOUT" != "" ]; then
            tm_now=$(date +'%s')
            tm_limit=$(( tm_start + $VIRSH_WAIT_FOR_TIMEOUT ))
            if [ $tm_now -gt $tm_limit ]; then
                if [ "$optQuiet" == "" ]; then
                    echo " ERROR"
                else
                    false ; check_status \
                        "failed to access VM '$vmname' "
                fi
                exit -1
            fi
        fi
        ipaddr=$(virsh-get-vm-ipaddr.sh $vmname)
        if [ $? -ne 0 ]; then
            verbose "missing IP address for $vmname"
            keep_trying=1
            break
        fi
        if [ "$optSkipPing" == "" ]; then
            ping -q -c 1 -W 1 "$ipaddr" > /dev/null
            if [ $? -ne 0 ]; then
                verbose "failed to ping ($ipaddr) $vmname"
                keep_trying=1
                break
            fi
        fi
        for port in ${checkPortList[@]} ; do
            nc -w 1 $ipaddr $port > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                verbose "could not access $ipaddr:$port ($vmname)"
                keep_trying=1
                break
            fi
        done
        if [ "$optCheckSSH" != "" ]; then
            ssh ${sshopts[@]} $ipaddr true
            if [ $? -ne 0 ]; then
                verbose "SSH to $ipaddr failed ($vmname)"
                keep_trying=1
                break
            fi
        fi
    done
    if [ $idx -gt 0 ]; then
        sleep 1
        if [ "$optQuiet" == "" ] && [ "$optVerbose" == "" ]; then
            echo -n '.'
        fi
    fi
    idx=$(( idx + 1 ))
done

if [ "$optQuiet" == "" ] && [ "$optVerbose" == "" ]; then
    echo " UP"
fi

verbose "all VMs are UP"

########################################################################
exit 0
