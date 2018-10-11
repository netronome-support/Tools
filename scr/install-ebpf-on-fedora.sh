#!/bin/bash

GREEN='\033[0;32m'
NC='\033[0m'
RED='\033[0;31m'

for arg in "$@" ; do
    if [ "$param" == "" ]; then
        case "$arg" in
            "--help"|"-h")
                echo "Usage: <package file>|<version>"
                exit 0
                ;;
            "--verbose"|"-v")   optVerbose="yes" ;;
            "--reinstall")      REINSTALL="yes" ;;
            "--version")        param="version" ;;
        *)
            if [ -f "$arg" ]; then
                pkgfile="$arg"
            else
                version="$arg"
            fi
            ;;
        esac
    else
        case "$param" in
            "version")          version="$arg" ;;
        esac
        param=""
    fi
done

############################################################
dldir="/var/cache/download"
ns_atchmnt_url="https://help.netronome.com/helpdesk/attachments"
deb_dl_dir="/var/cache/download/deb"
############################################################
function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg" >&2
        if [ $2 != 0 ]; then
            exit -1
        fi
    fi
}

############################################################
function check_version () {
    local cnt="$1" # Number of Numbers to compare
    # Version String Format: two substitutions are made:
    #    '#' - number  - regex: ([0-9]+)
    #    '.' - period  - regex: \.
    local fmt="$(echo $2 | sed -r 's/#/([0-9]+)/g;s/\./\\./g').*"
    local c_vers="$3" # Current Version
    local r_vers="$4" # Required Version
    local idx=1
    if [ "$c_vers" == "" ]; then
        return 1
    fi
    for (( idx=1 ; idx <= $cnt ; idx=idx+1 )) ; do
        local c_idx=$(echo $c_vers | sed -r 's/^'"$fmt"'$/'"\\$idx/")
        local r_idx=$(echo $r_vers | sed -r 's/^'"$fmt"'$/'"\\$idx/")
        test "$c_idx" != ""
            check_status "could not parse version number $c_vers"
        if [ $c_idx -lt $r_idx ]; then
            return 1
        fi
        if [ "$r_idx" == "" ]; then
            return 0
        fi
    done
    return 0
}

############################################################
function download () {
    local dldir="$1"
    local url="$2"
    local fname="$3"
    if [ -f "$dldir/$fname" ]; then
        return 0
    fi
    mkdir -p $dldir/pending
        check_status "failed to make directory $dldir"
    echo " - Download $url"
    wget --continue "$url" -O "$dldir/pending/$fname"
        check_status "failed to download $url ($fname)"
    mv $dldir/pending/$fname $dldir/$fname
        check_status "failed to move downloaded file"
    return 0
}
############################################################
echo " - Check OS Version and Kernel Version"

test -f /etc/os-release
    check_status "missing file /etc/os-release"

. /etc/os-release

test "$ID" == "fedora"
    check_status "This installation script requires Fedora"

test $VERSION_ID -ge 28
    check_status "This installation script requires at least Fedora 28"

check_version 2 "#.#" "$(uname -r)" "4.18"
    update_kernel=$?

check_version 2 "#.#" "$(uname -r)" "4.18"
    check_status "The Linux Kernel must be at least 4.18" 0  

if [ $update_kernel == 0 ]; then
    echo -e "${GREEN}OS Version and Kernel Version is sufficient${NC}"
fi

############################################################

while [ update_kernel == 1 ]; do
    read -p "Do you wish to update the Kernel? System will reboot after update. Please run this script again after reboot. (y/n)?" yn
    case $yn in
        [Yy]* )
        echo "Kernel will now be updated..."
        curl -s https://repos.fedorapeople.org/repos/thl/kernel-vanilla.repo | sudo tee /etc/yum.repos.d/kernel-vanilla.repo
        yum install kernel-devel -y
        dnf --enablerepo=kernel-vanilla-stable update -y
            check_status "failed to upgrade kernel"
        reboot;
        break;;
        [Nn]* ) echo "Exiting setup"; exit;;
        * ) echo "Please answer (y/n).";;
    esac
done  

############################################################

pkglist=()
pkglist+=( "wget@" "make@" "gcc@" "bc@" "bison@" "flex@" "git@" )
pkglist+=( "ethtool@" )
pkglist+=( "clang@" "pkg-config@" )
pkglist+=( "llc@llvm" )
pkglist+=( "bpftool@" )

pkglist+=( "/usr/src/kernels/$(uname -r)/Makefile@kernel-devel" )
pkglist+=( "/usr/include/bfd.h@binutils-devel" )
pkglist+=( "/usr/share/doc/elfutils@elfutils" )
pkglist+=( "/usr/include/libmnl/libmnl.h@libmnl-devel" )
pkglist+=( "/usr/include/ncurses.h@ncurses-devel" )
pkglist+=( "/usr/include/libelf.h@elfutils-libelf-devel" )

./install-packages.sh ${pkglist[@]} \
    || exit -1

############################################################
c_iproute_vers=$(ip -V | sed -rn 's/^.*-ss([0-9]+)$/\1/p')
if [ $c_iproute_vers -lt 180813 ]; then
    echo " - Upgrade iproute"
    dnf --enablerepo=updates-testing --best install -y iproute
        check_status "failed to upgrade iproute"
fi
############################################################
if [ ! -d /lib/modules/$(uname -r)/build/usr/include ]; then
    echo " - Install Linux Headers"
    make -C /lib/modules/$(uname -r)/build headers_install
        check_status "failed to install kernel headers"
    # Fedora seems to not keep old kernels around so this
    # will likely be a PITA constantly upgrading the kernel.
fi
############################################################
# Try to determine Firmware Version
fw_version=""
nfp_drv_dir="/sys/bus/pci/drivers/nfp"
if [ -d "$nfp_drv_dir" ]; then
    pcidir=$(find $nfp_drv_dir -type l -name '00*')
    if [ "$pcidir" != "" ] && [ -d $pcidir/net ]; then
        nfp_if_dir=$(find $pcidir/net -maxdepth 1 -mindepth 1 -type d | head -1)
        if [ -d $nfp_if_dir ]; then
            ifname=$(basename $nfp_if_dir)
            vstring=$(ethtool -i $ifname \
                | sed -rn 's/^firmware-version:\s+(\S.*)$/\1/p')
            nfd_version=$(echo $vstring | cut -d ' ' -f 1)
            nsp_version=$(echo $vstring | cut -d ' ' -f 2)
            fw_version=$(echo $vstring  | cut -d ' ' -f 3)
            fw_app_name=$(echo $vstring | cut -d ' ' -f 4)
        fi
    fi
fi

############################################################
upgrade=NO
check_version 4 "#.#.#.#" "$nfd_version" "0.0.3.5" || upgrade=YES
check_version 4 "bpf-#.#.#.#" "$fw_version" "bpf-2.0.6.121" || upgrade=YES
if [ "$upgrade" == "NO" ] && [ "$fw_app_name" == "ebpf" ]; then
    echo "DONE($fw_version already installed)"
    exit 0
fi

############################################################
if [ "$pkgfile" == "" ]; then
    attchid="36012574800" ; r_pkgvers="2.0.6.121-1"

    echo " - Install Agilio BPF Firmware"
    pkgfname="agilio-bpf-firmware-$r_pkgvers.noarch.rpm"
    download $deb_dl_dir "$ns_atchmnt_url/$attchid" "$pkgfname"
    pkgfile="$deb_dl_dir/$pkgfname"
fi
############################################################

rpm --install $pkgfile
    check_status "failed to install $pkgfile"

rmmod nfp > /dev/null 2>&1

echo " - Load NFP Driver with new firmware"
modprobe nfp
    check_status "modprobe of 'nfp' failed"

############################################################
echo "SUCCESS($(basename $0))"
exit 0
