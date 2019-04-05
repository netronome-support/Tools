#!/bin/bash

enable-netronome-repository.sh \
    || exit -1

install-packages.sh nfp-bsp-6000-b0 \
    || exit -1

exit 0
