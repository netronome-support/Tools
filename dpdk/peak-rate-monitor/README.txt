Maximum Rate Monitor - This DPDK-based tool measures the short-term bit- and
packet-rate of received traffic. It is based on DPDK's l2fwd and will forward
the traffic in a similar fashion.

Currently, the tool implements two methods for measuring short-term behavior:
1. Maximum Rates over 50 and 200 DPDK poll-mode loops.
2. Maximum Rates over minimum time window as specified on command line.

For the second mode, one can specify several 'monitors', where each monitor is configured via the following command line argument:

-m <port index>:<window in [ms]>:<dampening factor>

The dampening factor is multiplied to the maximum rate twice a second.

See the run-peak-rate-monitor.sh script for more details on how to run this tool.

The output of the tool may look like something like:

====================================================

Port statistics ====================================
Statistics for port 0 ------------------------------
Packets sent:                        0
Packets received:          10480225613
Packets dropped:                     0
Statistics for port 1 ------------------------------
Packets sent:              10480225809
Packets received:                    0
Packets dropped:                     0
Aggregate statistics ===============================
Total packets sent:        10480226029
Total packets received:    10480225809
Total packets dropped:               0
====================================================
Port     Most recent             Max(50)                 Max(200)               
              Kpps       Mbps         Kpps       Mbps         Kpps       Mbps   
   0:     1782.298    855.503     1888.953    906.697     1807.890    867.787 
   1:        0.000      0.000        0.000      0.000        0.000      0.000 

====================================================
Port   Window    PktRate    BitRate      Loops    Packets
         [ms]     [Mpps]     [Gbps]                      
   0  100.000      1.781      0.855      13020     178143
   0   10.000      1.785      0.857       1330      17855
   0    1.000      1.815      0.871        146       1819
   0    0.100      1.985      0.953          8        220
   0    0.010      2.882      1.384          8         60

====================================================
