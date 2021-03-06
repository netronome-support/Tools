#!/bin/bash

########################################################################
# This script is maintained at:
#   https://github.com/netronome-support/Tools
########################################################################
: ${GIT_REPO_BASE_DIR:=/opt/git}
: ${GITHUB_REPO_PATH:="netronome-support/Tools"}
: ${GIT_NS_TOOLS_REPO_DIR:="$GIT_REPO_BASE_DIR/netronome-support/Tools"}
: ${GIT_URL:="https://github.com/$GITHUB_REPO_PATH"}
########################################################################
tmpdir=$(mktemp --directory)
: ${logdir:=$HOME/.logs}
: ${logfile:=$logdir/install-netronome-support-tools.log}
mkdir -p $logdir
########################################################################
function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}
########################################################################
function run () {
    local cmd=( "$@" )
    local outlog="$tmpdir/output.log"
    printf "##  - %s\n##  %s\n" "$(date)" "${cmd[*]}" \
        | tee -a $logfile > $outlog
    "${cmd[@]}" 2>&1 \
        | tee -a $logfile > $outlog
    if [ $? -ne 0 ]; then
        echo "ERROR($(basename $0)): Command failed (log below)"
        echo "CMD: ${cmd[*]}"
        cat $outlog
        exit -1
    fi
}
########################################################################
which git > /dev/null 2>&1
if [ $? -ne 0 ]; then
    if which yum > /dev/null 2>&1 ; then
        run yum install -y git
    elif which apt-get > /dev/null 2>&1 ; then
        run apt-get update
        run apt-get install -y git
    else
        false ; check_status "missing package management tool"
    fi
fi
########################################################################

if [ ! -d $GIT_NS_TOOLS_REPO_DIR ]; then
    run git clone $GIT_URL $GIT_NS_TOOLS_REPO_DIR
else
    cd $GIT_NS_TOOLS_REPO_DIR
    run git fetch
fi

########################################################################

set -o pipefail
cmpcnt=$( \
    ( cd $GIT_NS_TOOLS_REPO_DIR && \
      git status --short && \
      git diff origin/master --name-status \
    ) | wc --lines | cut -d ' ' -f 1 \
    )
    check_status "failed to check status of GIT repo"

if [ $cmpcnt -ne 0 ]; then
    # GIT Repository is not 'clean', make a copy
    run cp -r $GIT_NS_TOOLS_REPO_DIR $tmpdir
    cd $tmpdir/Tools
    run git reset --hard
    run git checkout master
    run git merge origin/master
    GIT_NS_TOOLS_REPO_DIR="$tmpdir/Tools"
fi

########################################################################

run $GIT_NS_TOOLS_REPO_DIR/install.sh

########################################################################
rm -rf $tmpdir
########################################################################
exit 0
