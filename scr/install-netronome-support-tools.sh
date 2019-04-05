#!/bin/bash

: ${GIT_REPO_BASE_DIR:=/opt/git}
: ${GITHUB_REPO_PATH:="netronome-support/Tools"}
: ${GIT_NS_TOOLS_REPO_DIR:="$GIT_REPO_BASE_DIR/netronome-support/Tools"}
: ${GIT_URL:="https://github.com/$GITHUB_REPO_PATH"}

########################################################################
tmpdir=$(mktemp --directory)
########################################################################
function run () {
    local cmd="$@"
    local outlog="$tmpdir/output.log"
    $cmd > $outlog 2>&1
    if [ $? -ne 0 ]; then
        echo "CMD: $cmd"
        cat $outlog
        echo "ERROR($(basename $0))!"
        exit -1
    fi
}
########################################################################
if [ ! -d $GIT_NS_TOOLS_REPO_DIR ]; then
    run git clone $GIT_URL $GIT_NS_TOOLS_REPO_DIR
    run $GIT_NS_TOOLS_REPO_DIR/install.sh
else
    run git -C $GIT_NS_TOOLS_REPO_DIR fetch
    run cp -r $GIT_NS_TOOLS_REPO_DIR $tmpdir
    run git -C $tmpdir/Tools reset --hard
    run git -C $tmpdir/Tools checkout master
    run $tmpdir/Tools/install.sh
fi
########################################################################
rm -rf $tmpdir
########################################################################
exit 0
