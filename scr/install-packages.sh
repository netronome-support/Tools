#!/bin/bash

########################################################################

function usage () {
cat <<EOT

$0 - Check for and install packages (if needed)

Works with both Debian and RedHat based Linux distributions

Each argument corresponds to a package. Formats:

  <package information>
    - Always install this package

  <package and tool name>@<package information>
    - Check if the dependency exists, if not then install the package
      A dependency can either be an executible or a file
      A file must begin with the character '/'
      Example: virsh:libvirt-bin

  <package and tool name>@
    - Syntax useful for when tool name and package names are identical
      Example: tmux@

Package Information:

    This can be a plain package name. It can also be a comma-separated
    list of package candidates of one of the following formats:

        <OS name>:<package name>
        <package name> 

    The first entry will be used if the OS name matches. Typical
    OS names: ubuntu, debian, centos, redhat, fedora

    An entry of the second format will be used if no other entry
    matches.

    No package is installed if there is no match.

EOT
}

########################################################################

if which apt-get > /dev/null 2>&1 ; then
    insttool="apt-get"
    OS_ID_LIKE="debian ubuntu"
elif which yum > /dev/null 2>&1 ; then
    insttool="yum"
    OS_ID_LIKE="redhat fedora centos"
else
    echo "ERROR: unable to determine package installation tool"
    exit -1
fi

if [ -f /etc/os-release ]; then
    OS_ID="$(cat /etc/os-release \
        | sed -rn 's/^ID=//p' \
        | tr -d '"')"
    OS_ID_LIKE="$(cat /etc/os-release \
        | sed -rn 's/^ID_LIKE=//p' \
        | tr -d '"')"
fi

########################################################################

function repository_update () {
    case "$insttool" in
      "yum")
        udtagfile="/var/lib/.yum-update-tag-file.txt"
        if [ ! -f "$udtagfile" ]; then
            $PKGMGR update -y >> $pkgmgrlog 2>&1
            echo "Created by $0 on $(date)" > $udtagfile
        fi
        ;;
      "apt-get")
        if [ "$PKG_UPDATE_MAX_AGE" != "" ]; then
            if test $(find /var/lib/apt -type d -name 'lists' \
                -mmin +$PKG_UPDATE_MAX_AGE) ; then
                apt-get update || exit -1
            fi
        else
            apt-get update || exit -1
        fi
        ;;
  esac
   
}

########################################################################

function identify_package () {
    local pkginfo="$1"
    local pkg_default=""
    local pkg_like=""
    local idx=1
    if [ "${pkginfo/*,*}" != "" ]; then
        pkginfo="$pkginfo,"
    fi
    while : ; do
        local field=$(echo $pkginfo | cut -d ',' -f $idx)
        if [ "$field" == "" ]; then
            break
        fi
        if [ "${field/*:*/}" == "" ]; then
            local f_osname="${field/:*/}"
            local f_pkgname="${field/*:/}"
            if [ "$f_osname" == "$OS_ID" ] ; then
                pkgname="$f_pkgname"
                return
            fi
            for id in $OS_ID_LIKE ; do
                if [ "$f_osname" == "$id" ]; then
                    pkg_like="$f_pkgname"
                fi
            done
        else
            pkg_default="$field"
        fi
        idx=$(( idx + 1 ))
    done
    if [ "$pkg_like" != "" ]; then
        pkgname="$pkg_like"
    else
        pkgname="$pkg_default"
    fi
}

########################################################################

pkglist=()

function cond_add_tool () {
    local toolinfo="$1"
    local pkgname="$2"
    if [ "${toolinfo:0:1}" == "/" ]; then
        # If first character is a '/', then cheack for a file
        if [ ! -f "$toolinfo" ]; then
            pkglist+=( "$pkgname" )
        fi
    else
        if [ "$(which -a $toolinfo 2> /dev/null)" == "" ]; then
            pkglist+=( "$pkgname" )
        fi
    fi
}

########################################################################

function parse_package_entry () {
    local arg="$1"
    local toolinfo="$(echo $arg | cut -d '@' -f 1)"
    local pkginfo="$(echo $arg | cut -d '@' -f 2)"
    if [ "$pkginfo" == "" ]; then
        # Tool and package have the same name
        cond_add_tool "$toolinfo" "$toolinfo"
    else
        # Determine package name
        identify_package "$pkginfo"
        if [ "$pkgname" != "" ]; then
            if [ "$toolinfo" == "" ]; then
                pkglist+=( "$pkgname" )
            else
                cond_add_tool "$toolinfo" "$pkgname"
            fi
        fi
    fi
}

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
        "--update"|"--cache-update")
            opt_update="yes"
            ;;
        "-n"|"--dry-run")
            opt_dryrun="yes"
            ;;
        "-l"|"--log-file") param="--log-file" ;;
        "--update-max-age") param="$arg" ;;
        *)
            parse_package_entry "$arg"
            ;;
        esac
    else
        case "$param" in
        "--log-file") PKG_LOG_FILE="$arg" ;;
        "--update-max-age") PKG_UPDATE_MAX_AGE="$arg" ;;
        esac
        param=""
    fi
done

########################################################################

if [ "$opt_dryrun" != "" ]; then
    echo "Would install: ${pkglist[@]}"
    exit 0
fi

########################################################################

if [ ${#pkglist[@]} -eq 0 ]; then
    exit 0
fi

########################################################################

if [ "$opt_update" != "" ]; then
    repository_update
fi

########################################################################

if [ "$PKG_LOG_FILE" != "" ]; then
    exec $insttool install -y ${pkglist[@]} \
        > $PKG_LOG_FILE 2>&1
else
    exec $insttool install -y ${pkglist[@]}
fi

########################################################################
