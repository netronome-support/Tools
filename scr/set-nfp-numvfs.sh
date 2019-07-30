#!/bin/bash

############################################################
# This script is maintained at:
#   https://github.com/netronome-support/Tools
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
param=""
nfpidx=0
for arg in "$@" ; do
    if [ "$param" == "" ]; then
        case "$arg" in
          "-h"|"--help")
            echo "Usage: $0 [--at-least] [--nfp-idx <#>] <VF Count>"
            exit 0
            ;;
          "-v"|"--verbose") optVerbose="yes" ;;
          "-m"|"--minimum"|"--at-least") optMinimum="yes" ;;
          "-n"|"--nfp-idx") param="--nfp-idx" ;;
          *)
            test "${arg:0:1}" != "-"
                check_status "failed to parse '$arg'"
            req_num_vfs="$arg"
            ;;
        esac
    else
        case "$param" in
          "--nfp-idx") nfpidx=$arg ;;
        esac
        param=""
    fi
done
############################################################
##  Verify that 'req_num_vfs' is an integer
re_integer='^[0-9]+$'
test "$req_num_vfs" != ""
    check_status "please specify number of VFs"
if [[ ! "$req_num_vfs" =~ $re_integer ]]; then
    false ; check_status "argument is not an integer ($req_num_vfs)"
fi
############################################################
##  Retrieve list of NFPs and check that 'nfpidx' exists
nfp_pci_list=( $(lspci -d 19ee: -s '00.0' \
    | cut -d ' ' -f 1 ) )
test ${#nfp_pci_list[@]} -gt 0
    check_status "there is no NFP detected on the PCI bus"
if [[ ! "$nfpidx" =~ $re_integer ]]; then
    false ; check_status "NFP index is not an integer ($nfpidx)"
fi
nfp_bdf="${nfp_pci_list[$nfpidx]}"
test "$nfp_bdf" != ""
    check_status "there is no NFP with index $nfpidx"
############################################################
##  Check that the 'sysfs' file 'sriov_numvfs' file exists
nfp_pci_dir="/sys/bus/pci/devices/0000:$nfp_bdf"
test -d $nfp_pci_dir
    check_status "missing PCI 'sysfs' directory ($nfp_pci_dir)"
nfp_pci_sriov_numvfs_file="$nfp_pci_dir/sriov_numvfs"
test -f $nfp_pci_sriov_numvfs_file
    check_status "missing $nfp_pci_sriov_numvfs_file"
############################################################
##  Check if enough VFs are already allocated
cur_num_vfs=$(cat $nfp_pci_sriov_numvfs_file)
if [ $cur_num_vfs -eq $req_num_vfs ]; then
    exit 0
fi
if [ "$optMinimum" != "" ]; then
    if [ $cur_num_vfs -gt $req_num_vfs ]; then
        exit 0
    fi
fi
############################################################
##  Check how many VFs are allowed
nfp_pci_sriov_totalvfs_file="$nfp_pci_dir/sriov_totalvfs"
test -f $nfp_pci_sriov_totalvfs_file
    check_status "missing $nfp_pci_sriov_totalvfs_file"
max_num_vfs=$(cat $nfp_pci_sriov_totalvfs_file)
test $max_num_vfs -gt 0
    check_status "SR-IOV is disabled (totalvfs is '0')"
test $req_num_vfs -le $max_num_vfs
    check_status "device supports up to $max_num_vfs VFs"
############################################################
##  The operation of re-configuring the numvfs is error-prone
##  and sometimes get stuck, so let's do it in a separate script.
tmpdir=$(mktemp --directory)
scrfile="$tmpdir/change.sh"
logfile="$tmpdir/output.log"
####################
cat <<EOF > $scrfile
#!/bin/bash

echo 0 > $nfp_pci_sriov_numvfs_file
echo $req_num_vfs > $nfp_pci_sriov_numvfs_file
EOF
####################
chmod a+x $scrfile
############################################################
$scrfile > $logfile 2>&1 &
pid=$!
############################################################
##  Wait for script to terminate
time_start=$(date +'%s')
time_limit=$(( time_start + 5 ))

while [ -d /proc/$pid ] ; do
    sleep 0.1
    time_now=$(date +'%s')
    test $time_now -lt $time_limit
        check_status "time-out trying to enable NFP SR-IOV VFs"
done

wait $pid
    check_status "failed to enable NFP SR-IOV VFs"
############################################################
rm -fr $tmpdir
############################################################
exit 0
