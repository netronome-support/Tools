#!/bin/bash

############################################################
##  Allow for local variable overrides
if [ -d $HOME/.config/netronome ]; then
    for fname in $(find $HOME/.config/netronome -name '*.sh') ; do
        . $fname
    done
fi
############################################################
##  Default Settings
if [ "$(whoami)" == "root" ]; then
    : ${DOWNLOAD_CACHE_DIR:="/var/cache/download"}
    : ${PKG_INSTALL_BASE_DIR:=/opt/pkg}
    : ${GIT_REPO_BASE_DIR:="/opt/git"}
else
    : ${DOWNLOAD_CACHE_DIR:="$HOME/.cache/download"}
    : ${PKG_INSTALL_BASE_DIR:="$HOME/opt/pkg"}
    : ${GIT_REPO_BASE_DIR:="$HOME/git"}
fi
############################################################
ns_atchmnt_url="https://help.netronome.com/helpdesk/attachments"
git_repo_base_dir="/opt/git"
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
    local penddir="$dcdir/.pending"
    if [ -f "$dldir/$fname" ]; then
        return 0
    fi
    mkdir -p $penddir
        check_status "failed to make directory $penddir"
    echo " - Download $url"
    wget --continue "$url" -O "$penddir/$fname"
        check_status "failed to download $url ($fname)"
    mv $penddir/$fname $dldir/$fname
        check_status "failed to move downloaded file"
}
############################################################
echo " - Check Ubuntu OS Version"

test -f /etc/os-release
    check_status "missing file /etc/os-release"

. /etc/os-release

test "$ID" == "ubuntu" -a "$VERSION_ID" == "18.04"
    check_status "this installation script requires Ubuntu 18.04"

############################################################

if test $(find /var/lib/apt -type d -name 'lists' -mmin +10080) ; then
    apt-get update
        check_status "failed to update Debian package database"
fi

############################################################

pkgs=()
pkgs+=( make gcc libelf-dev bc build-essential binutils-dev )
pkgs+=( ncurses-dev libssl-dev util-linux pkg-config elfutils )
pkgs+=( libreadline-dev libmnl-dev bison flex git wget )
pkgs+=( "initramfs-tools" ) # Missed in the documentation
pkgs+=( ethtool )

apt-get install -y ${pkgs[@]}
    check_status "failed to install packages"

############################################################

check_version 2 "#.#" "$(uname -r)" "4.18"
if [ $? -ne 0 ]; then
    install-linux-kernel-from-git.sh
        check_status ""

    printf "\n\n!! PLEASE REBOOT and reissue command !!\n\n\n"
    exit -1
fi

############################################################
if [ ! -d /lib/modules/$(uname -r)/build/usr/include ]; then
    echo " - Install Linux Headers"
    make -C /lib/modules/$(uname -r)/build headers_install
        check_status "failed to install kernel headers"
fi

############################################################
if [ ! -x /usr/bin/llvm-mc-6.0 ]; then
    echo " - Install LLVM"

cat <<EOF > /etc/apt/sources.list.d/llvm.list
# Added by $0 on $(date)
deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic-6.0 main
deb-src http://apt.llvm.org/bionic/ llvm-toolchain-bionic-6.0 main
EOF

    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 15CF4D18AF4F7421
        check_status "failed to add key"
    apt-get update
        check_stauts "failed to update package database"
    apt-get install -y clang-6.0
        check_status "failed to install 'clang' package"

    update-alternatives --install /usr/bin/clang    clang   /usr/bin/clang-6.0 100
        check_status "Intalling clang alternative failed"

    update-alternatives --install /usr/bin/clang++  clang++ /usr/bin/clang++-6.0 100
        check_status "Intalling clang++ alternative failed"

    update-alternatives --install /usr/bin/llc      llc     /usr/bin/llc-6.0 100
        check_status "Intalling llc alternative failed"

    update-alternatives --install /usr/bin/llvm-mc  llvm-mc /usr/bin/llvm-mc-6.0 50
        check_status "Intalling llvm-mc alternative failed"
fi

############################################################

git_url="https://git.kernel.org/pub/scm/network/iproute2"
git_repo_name="iproute2-next"
git_repo_dir="$git_repo_base_dir/$git_repo_name"

if ! which ip > /dev/null 2>&1 ; then
    iproute2_version=""
else
    iproute2_version="$(ip -V | sed -r 's/^.*iproute2-//')"
fi

check_version 1 "ss#" "$iproute2_version" "180813"
if [ $? -ne 0 ]; then
    echo " - Install iproute2"

    if [ -d "$git_repo_dir/.git" ]; then
        git -C $git_repo_dir pull
            check_status "failed to update GIT repo $git_repo_dir"
    else
        mkdir -p $git_repo_base_dir
        git -C $git_repo_base_dir clone $git_url/$git_repo_name.git
            check_status "failed to clone repo $git_url/$git_repo_name.git"
    fi
    {   echo " - Build iproute2"
        cd $git_repo_base_dir/$git_repo_name \
            && ./configure \
            && make \
            && make install
    }
        check_status "failed to build & install $git_repo_name"
fi

############################################################
##  Strange fix which enables one to compile ebpf applications
ln -sf /usr/include/x86_64-linux-gnu/asm /usr/include
    check_status "failed to create symbolic link"

############################################################
if ! which bpftool > /dev/null 2>&1 ; then
    bpftool_version=""
else
    bpftool_version="$(bpftool --version | cut -d ' ' -f 2)"
fi

check_version 3 "v#.#.#" "$bpftool_version" "v4.17.0"
if [ $? -ne 0 ]; then
    echo " - Install bpftool ($bpftool_version)"
    bpfdir="$git_repo_base_dir/linux/tools/lib/bpf"
    test -d $bpfdir
        check_status "missing directory $bfpdir"
    make -C $bpfdir
        check_status "faild to build $bpfdir"
    make -C $bpfdir install
        check_status "failed to install $bpfdir"
    make -C $bpfdir install_headers
        check_status "failed to install headers $bpfdir"
    ldconfig
        check_status "ldconfig returned with error"
fi
############################################################
c_pkgvers=$(apt-cache show bpftool 2> /dev/null \
    | sed -rn 's/^Version:\s(\S+)$/\1/p')

# Sorry, these 'attachment numbers' is a bad way of referencing packages,
# but at the moment I don't know of anything better.
attachid="36014191625" ; r_pkgvers="4.18"
attachid="36025601060" ; r_pkgvers="4.20"


check_version 2 "#.#" "$c_pkgvers" "$r_pkgvers"
if [ $? -ne 0 ]; then
    deb_dl_dir="$DOWNLOAD_CACHE_DIR/deb"
    pkgfname="bpftool-${r_pkgvers}_amd64.deb"
    download $deb_dl_dir "$ns_atchmnt_url/$attachid" "$pkgfname"

    dpkg -i $deb_dl_dir/$pkgfname
        check_status "failed to install $pkgfname"
fi

############################################################
c_pkgvers=$(apt-cache show agilio-bpf-firmware 2> /dev/null \
    | sed -rn 's/^Version:\s(\S+)$/\1/p')

attchid="36019898763" ; r_pkgvers="2.0.6.124-1"

check_version 4 "#.#.#.#" "$c_pkgvers" "$r_pkgvers"
if [ $? -ne 0 ]; then
    echo " - Install Netronome eBPF Firmware"
    pkgfname="agilio-bpf-firmware-$r_pkgvers.deb"
    deb_dl_dir="$DOWNLOAD_CACHE_DIR/deb"
    download $deb_dl_dir "$ns_atchmnt_url/$attchid" "$pkgfname"

    dpkg -i $deb_dl_dir/$pkgfname
        check_status "failed to install $pkgfname"

    update-initramfs -u
        check_status "'update-initramfs -u' failed"

    rmmod nfp > /dev/null 2>&1

    modprobe nfp
        check_status "modprobe of 'nfp' failed"
fi

############################################################
echo "SUCCESS($(basename $0))"
exit 0
