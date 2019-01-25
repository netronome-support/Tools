#!/bin/bash

########################################
# Command Line Parsing

param=""
pagecnt=""
mntpnt="/dev/hugepages"
: "${hugepage_size:=2048}"

for arg in "$@" ; do
    if [ "$param" == "" ]; then
        case "$arg" in
          "--help"|"-h")
            echo "Allocate Hugepages"
            echo "  --help -h"
            echo "  --verbose -v"
            echo "  --min-pages|--max-pages"
            echo "  --mount-point <directory>"
            echo "  --page-size 2MB|1GB"
            exit
            ;;
          "--verbose"|"-v")     optVerbose="yes" ;;
          "--min-pages")        optLimitPages="min" ;;
          "--max-pages")        optLimitPages="max" ;;
          "--mount-point")      param="mount-point" ;;
          "--page-size")        param="page-size" ;;
          *)
            if [ "$pagecnt" != "" ]; then
                echo "ERROR: too many arguments"
                exit -1
            fi
            re='^[0-9]+$'
            if [[ ! $arg =~ $re ]]; then
                echo "ERROR: invalid page count argument ($arg)"
                exit -1
            fi
            pagecnt="$arg"
            ;;
        esac
    else
        case "$param" in
          "mount-point") mntpnt="$arg" ;;
          "page-size")
            case "$arg" in
              "2M"|"2MB"|"2048"|"2048K"|"2048KB")
                hugepage_size="2048" ;;
              "1G"|"1GB")
                hugepage_size="1048576" ;;
              *)
                echo "ERROR: illegal page size ($arg)"
                exit -1
                ;;
            esac
            ;;
        esac
        param=""
    fi
done

########################################
grep --quiet 'hugetlbfs' /proc/mounts
if [ $? -ne 0 ]; then
    mkdir -p $mntpnt || exit -1
    mount -t hugetlbfs huge $mntpnt || exit -1
fi

########################################
if [ "$pagecnt" == "" ]; then
    exit 0
fi

########################################
sys_hp_file="/sys/kernel/mm/hugepages/hugepages-${hugepage_size}kB/nr_hugepages"
if [ ! -f $sys_hp_file ]; then
    echo "ERROR: missing $sys_hp_file"
    exit -1
fi

########################################
change="YES"
if [ "$optLimitPages" != "" ]; then

    cur_pages=$(cat /proc/meminfo \
        | sed -rn 's/^HugePages_Total:\s+(\S+)$/\1/p')

    case "$optLimitPages" in
        "min")
            if [ $cur_pages -gt $pagecnt ]; then
                change="NO"
            fi
            ;;
        "max")
            if [ $cur_pages -lt $pagecnt ]; then
                change="NO"
            fi
            ;;
    esac
fi
########################################
if [ "$change" == "YES" ]; then
    echo $pagecnt > $sys_hp_file \
        || exit -1
fi
########################################
exit 0
