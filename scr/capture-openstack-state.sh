#!/bin/bash

########################################################################
capfile="$HOME/openstack-capture-$(date +'%Y-%m-%d-%H%M').txt"
########################################################################
set -o pipefail
########################################################################
opts=()
opts+=( "--max-width" "100" )
########################################################################

function check_status () {
    local rc=$?
    local errmsg="$1"
    if [ $rc -ne 0 ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}

function section () {
    local name="$1"
    printf "\n\n--  %s\n\n" "$name" \
        | tee -a $capfile
}

########################################################################
##  OpenStack Credentials

# OpenStack Credentials Candidate List
os_cc_list=()
os_cc_list+=( "/etc/contrail/openstackrc" )
os_cc_list+=( "/etc/kolla/admin-openrc.sh" )

if [ "$OS_AUTH_URL" == "" ]; then
    for ccfile in ${os_cc_list[@]} ; do
        if [ -f "$ccfile" ]; then
            . $ccfile
            break
        fi
    done
    if [ "$OS_AUTH_URL" == "" ]; then
        echo "ERROR: can't find OpenStack credentials"
        exit -1
    fi
fi

########################################################################
section "General Information"

{   echo "Date: $(date)"
    uname -a
    echo "Host: $(hostname)"
    echo
    printenv \
        | grep -E '^OS_' \
        | grep -v 'PASSWORD'
    echo
    cat /etc/os-release
} | tee -a $capfile

########################################################################
section "OpenStack Version"

openstack --version "${opts[@]}" 2>&1 \
    | tee -a $capfile
    check_status "'openstack --version' failed"

########################################################################
##  Objects that can be dumped via a simple 'list' command

objlist=()

for objname in ${objlist[@]} ; do
    section "OpenStack '$objname'"
    openstack $objname list "${opts[@]}" \
        | tee -a $capfile
        check_status "'openstack $objname list' failed"
done

########################################################################
##  Objects that can be dumped by showing each object

objlist=()
objlist+=( "hypervisor" )
objlist+=( "server" )
objlist+=( "image" )
objlist+=( "flavor" )
objlist+=( "router" )
objlist+=( "network" )
objlist+=( "subnet" )
objlist+=( "port" )
objlist+=( "floating ip" )
objlist+=( "security group" )
objlist+=( "aggregate" )
objlist+=( "project" )
objlist+=( "user" )
objlist+=( "role" )
objlist+=( "keypair" )

for objname in "${objlist[@]}" ; do
    fieldname="ID"
    section "OpenStack '$objname' list:"

    openstack $objname list "${opts[@]}" \
        | tee -a $capfile
        check_status "'openstack $objname list' failed"
    case "$objname" in
        "keypair") fieldname="Name" ;;
    esac
    id_list=$(openstack $objname list -f value -c "$fieldname")
    for objid in $id_list ; do
        openstack $objname show $objid "${opts[@]}" \
            | tee -a $capfile
            check_status "'openstack $objname show $objid' failed"
    done
done

########################################################################

section "quota"
openstack quota show "${opts[@]}" \
    | tee -a $capfile
    check_status "openstack --version failed"

########################################################################

exit 0
