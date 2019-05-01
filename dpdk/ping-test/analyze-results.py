#!/usr/bin/env python

import sys
import pprint

llist = []

def parse_file(fname):
    with open(fname, 'r') as fp:
        count = 0
        for line in fp:
            lat = float(line)
            count = count +1
            llist.append(lat)

parse_file(sys.argv[1])

llist.sort()

# List Length (number of samples in list)
llen = len(llist)

if (llen == 0):
    print('ERROR: no samples available!')
    exit(-1)

def print_result(desc, value):
    print('  {desc:30} {val:9.1f} us'.format(desc = desc, val = value))

def print_best(ratio):
    global llist
    global llen
    total = 0.0
    count = int(llen * ratio / 100.0)
    if (count == 0) or (count >= llen):
        return
    for idx in range(count):
        total = total + llist[idx]
    desc = 'Average (best {r:2}% = {cnt})' \
        .format(r = int(ratio), cnt = count)
    print_result(desc, total / count)

def print_sample(desc, index):
    if (index >= llen):
        return
    print_result(desc, llist[index])

print('Samples: ' + str(llen))

print_sample('Median', int(llen / 2))

total = 0.0
for item in llist:
    total = total + item

print_result('Average', total / llen)

print_sample('Best', 0)
print_sample('Worst', llen - 1)

print_best(1)
print_best(10)
print_best(50)
print_best(90)
print_best(99)

print_sample(' 1 Percentile', int(llen * 0.01))
print_sample(' 5 Percentile', int(llen * 0.05))
print_sample('10 Percentile', int(llen * 0.10))
print_sample('90 Percentile', int(llen * 0.90))
print_sample('95 Percentile', int(llen * 0.95))
print_sample('99 Percentile', int(llen * 0.99))
