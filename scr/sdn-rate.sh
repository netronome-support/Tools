#!/bin/bash

args=""

args="$args --long --norm --list-drop --pktsize"
args="$args --reset"
args="$args --ignore-zero"
args="$args -i 1"
args="$args --total-start"

args="$args "$(cat /proc/net/dev \
  | sed -rn 's/^\s*(sdn_p[0-9]):.*$/\1/p' \
  | sort)

args="$args "$(cat /proc/net/dev \
  | sed -rn 's/^\s*(nfp_p[0-9]):.*$/\1/p' \
  | sort)

args="$args --total"

args="$args sdn_pkt"
args="$args --total-start"

args="$args "$(cat /proc/net/dev \
  | sed -rn 's/^\s*(sdn_v.*):.*$/\1/p' \
  | sort -V)

args="$args "$(cat /proc/net/dev \
  | sed -rn 's/^\s*(nfp_v.*):.*$/\1/p' \
  | sort -V)


args="$args --total"

exec rate $args
