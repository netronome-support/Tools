#!/bin/bash

########################################
# This script is maintained at:
#   https://github.com/netronome-support/Tools
########################################

function check_status () {
    rc="$?" ; errmsg="$1"
    if [ "$rc" != "0" ]; then
        echo "ERROR($(basename $0)): $errmsg"
        exit -1
    fi
}

########################################

function run () {
    local cmd="$@"
    printf "%s\nCMD: %s\n" "----" "$cmd" >> $logfile
    $cmd 2>&1 \
        | tee -a $logfile \
        > $outlog
    if [ $? -ne 0 ]; then
        echo "CMD: $cmd"
        cat $outlog
        echo "ERROR($(basename $0))!"
        exit -1
    fi
}

function info () {
    local level="$1"
    local str="$2"
    if [ "$optVerbose" != "" ]; then
        printf "%s\n" "$str"
    fi
    printf "%s\n" "$str" >> $logfile
}

########################################
set -o pipefail
########################################
##  Get local settings (if available)
cfg_file_list=()
cfg_file_list+=( "/etc/default/git-repo-config.sh" )
cfg_file_list+=( "$HOME/.config/git-repo-config.sh" )
for cfgfile in ${cfg_file_list[@]} ; do
    if [ -f "$cfgfile" ]; then
        . $cfgfile
    fi
done
########################################
##  Default Bare Repository Location
if [ "$(whoami)" == "root" ]; then
    : ${git_bare_base_dir:=/opt/git/bare-repos}
else
    : ${git_bare_base_dir:=$HOME/.local/git/bare-repos}
fi
########################################
##  Parse command line

param=""
git_repo_url=""
for arg in "$@" ; do
    if [ "$param" == "" ]; then
        case "$arg" in
            "--help"|"-h")
                echo "Usage: <package file>|<version>"
                exit 0
                ;;
            "--verbose"|"-v")   optVerbose="yes" ;;
            "--quiet"|"-q")     optVerbose="yes" ;;
            "--wipe-existing")  optWipeExisting="yes" ;;
            "--keep-existing")  optKeepExisting="yes" ;;
            "--tag")            param="$arg" ;;
            "--branch")         param="$arg" ;;
            "--name")           param="$arg" ;;
            "--reinstall")      install="yes" ;;
            "--force")          install="yes" ;;
        *)
            test "${arg:0:1}" != "-"
                check_status "failed to parse '$arg'"
            if [ "$git_repo_url" == "" ]; then
                git_repo_url="$arg"
            elif [ "$git_repo_dir" == "" ]; then
                git_repo_dir="$arg"
            else
                :
            fi
            ;;
        esac
    else
        case "$param" in
            "--branch")         git_repo_branch="$arg" ;;
            "--tag")            git_repo_tag="$arg" ;;
            "--repo-path")      git_repo_path="$arg" ;;
        esac
        param=""
    fi
done

test "$param" == ""
    check_status "argument missing for '$param'"

########################################
test "$git_repo_url" != ""
    check_status "please specify Git repository URL"
########################################
if [ "$git_repo_path" == "" ]; then
    git_repo_path=$(echo $git_repo_url \
        | sed -r 's#^\S+://##' \
        | sed -r 's#\.git$##' \
        )
fi
if [ "$git_repo_name" == "" ]; then
    git_repo_name=$(echo $git_repo_path \
        | tr '/' '-' \
        )
fi
git_bare_repo_dir="$git_bare_base_dir/$git_repo_path"
########################################
##  Log file locations
logdir="$git_bare_base_dir/log"
mkdir -p $logdir
    check_status "failed to create $logdir"
outlog=$(mktemp /tmp/.log-cmd-XXXX.log)
logfile="$logdir/git-checkout-$git_repo_name.log"
########################################
if [ "$git_repo_dir" == "" ]; then
    git_repo_dir="$git_repo_path"
fi
########################################
cat <<EOF >> $logfile

----------------------------------------
DATE: $(date)
CMD: $0 $@
REPO PATH: $git_repo_path
REPO NAME: $git_repo_name
BARE REPO: $git_bare_repo_dir
DIR: $git_repo_dir
EOF
########################################
##  Update/clone local 'bare' repository

if [ ! -d $git_bare_repo_dir/.git ]; then
    info 1 " - Clone repo to "$git_bare_repo_dir
    rm -rf $git_bare_repo_dir
    run mkdir -p $git_bare_repo_dir
    cmd=( git clone )
    cmd+=( --no-checkout )
    cmd+=( "$git_repo_url" )
    cmd+=( "$git_bare_repo_dir" )
    run "${cmd[@]}"
else
    info 1 " - Fetch repo"
    ( cd $git_bare_repo_dir ; run git fetch )
fi

########################################

if [ -d "$git_repo_dir" ]; then
    cmpcnt=$( \
        cd $git_repo_dir ; \
        git status --short \
            | wc --lines \
            | cut -d ' ' -f 1 \
    )
        check_status "failed to check status of GIT repo"
    if [ $cmpcnt -eq 0 ]; then
        info 1 " - Pull repository"
        ( cd $git_repo_dir ; run git pull )
    elif [ "$optWipeExisting" != "" ]; then
        info 1 " - Wipe-out existing repository"
        rm -rf "$git_repo_dir"
    else
        cd "$git_repo_dir"
        name="stash-$(date +'%Y-%m-%d-%H%M%S')"
        info 1 " - Create STASH '$name', then pull"
        ( cd $git_repo_dir ; run git stash save $name )
        ( cd $git_repo_dir ; run git pull )
    fi
fi

if [ ! -d "$git_repo_dir" ]; then
    cmd=( git clone )
    cmd+=( --local )
    cmd+=( --shared )
    if [ "$git_repo_branch" != "" ]; then
        cmd+=( --branch "$git_repo_branch" )
    fi
    cmd+=( "$git_bare_repo_dir" )
    cmd+=( "$git_repo_dir" )
    info 1 " - Clone repo to $git_repo_dir"
    run "${cmd[@]}"
    if [ "$git_repo_branch" != "" ]; then
        cd $git_repo_dir
        run git checkout -b $git_repo_branch
    fi
fi

########################################
info 1 "SUCCESS"
exit 0
