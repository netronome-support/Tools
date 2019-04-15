#!/bin/bash

########################################

enable-netronome-repository.sh \
    || exit -1

install-packages.sh nfp-bsp-6000-b0 \
    || exit -1

########################################
# Note, for CPP access to work one needs to build via
#   install-nfp-drv-kmods.sh 

cat <<EOF > /etc/modprobe.d/nfp-cpp.conf
# Added by $0 on $(date)
options nfp nfp_dev_cpp=1
EOF

########################################
exit 0
