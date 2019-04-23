#!/bin/bash

############################################################
: ${AWAIT_IF_MAX_TIME:=20}
############################################################
function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        if [ "$errmsg" != "" ]; then
            echo "ERROR($(basename $0)): $errmsg" >&2
        fi
        exit -1
    fi
}
############################################################
##  Parse command line

param=""
for arg in "$@" ; do
    if [ "$param" == "" ]; then
        case "$arg" in
            "--help"|"-h")
                echo "Usage: <interface> [--up-and-running]"
                exit 0
                ;;
            "--verbose"|"-v")   optVerbose="yes" ;;
            "--up-and-running") optUpAndRunning="yes" ;;
            "--time-out")       param="time-out" ;;
        *)
            ifname="$arg"
            ;;
        esac
    else
        case "$param" in
            "time-out") AWAIT_IF_MAX_TIME="$arg" ;;
        esac
        param=""
    fi
done

test "$param" == ""
    check_status "argument missing for '--$param'"

############################################################
function verbose () {
    local msg="$1"
    if [ "$optVerbose" != "" ]; then
        printf "$msg"
    fi
}
############################################################
time_start=$(date +'%s')
time_max=$(( time_start + AWAIT_IF_MAX_TIME ))
while : ; do
    grep -E "^\s*$ifname:" /proc/net/dev > /dev/null
    if [ $? -eq 0 ]; then
        break
    fi
    sleep 0.25
    time_now=$(date +'%s')
    test $time_now -lt $time_max
        check_status "interface $ifname did not appear"
done
############################################################
if [ "$optUpAndRunning" != "" ]; then
    verbose " - Waiting for $ifname ..."
    time_start=$(date +'%s')
    time_max=$(( time_start + AWAIT_IF_MAX_TIME ))
    while : ; do
        line=$(ifconfig $ifname \
            | head -1 \
            | sed -rn 's/^.*<(\S*)>.*$/ \1 /p' \
            | tr ',' ' ')
        echo "$line" | grep -E '\sUP.*\sRUNNING\s' > /dev/null
        if [ $? -eq 0 ]; then
            break
        fi
        time_now=$(date +'%s')
        test $time_now -lt $time_max
            check_status "interface $ifname did not appear"
        if [ $time_now -gt $time_max ]; then
            printf "\n"
            false
            check_status "interface $ifname did not reach RUNNING state"
        fi
        sleep 0.25
        verbose "."
    done
    verbose " UP\n"
fi
############################################################

exit 0
