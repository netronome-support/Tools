This is a DPDK based tool that implements a simple IPv4 router.

It is based on l2fwd of DPDK 16.11 (see main.c file).

Features:

 * ARP - Will both resolve addresses as well as respond to requests.

 * ICMP - Will respond to ping requests.

 * DHCP - Will attempt to discover the interface IP address and subnet
   mask (if not explicitly specified on the command line).

 * IP forwarding - Will route packets between subnets and follow 
   explicit routes. Source and destination MAC address will be updated
   appropriately.

 * Routing Domains - Supports routing domains (identified by a unique
   routing domain index). Can thus act as multiple routers. By
   default, each port and route is associated with routing domain '1'.


Command Line Arguments (beyond what l2fwd supports):

 --iface-addr <portid>:[<route domain>#][<IPv4 addr>[/<prefix length>]]

    With this argument, which can be repeated once for each port, one
    can specify the IP address, subnet prefix length, and routing
    domain of each port. If no IP address is specified for a port,
    it will attempt to discover the IP address via DHCP. The routing
    domain defaults to '1' if not specified.

 --route [<route domain>#]<IPv4 addr>/<prefix length>@<next hop IPv4 addr>

    This adds a route to the specified (or default) routing domain.

 --static [<route domain>#]<next hop IPv4 addr>@<MAC address>

    Add static ARP entry.

 --pin <portid>:<RX & TX lcore>
 --pin <portid>:<RX lcore>,<TX lcore>

    Assign a port to logical cores (0..)

 --ping-nexthops

    Regularly (once per second) ping all route nexthops.

 --no-statistics

    Do not print statistics to standard output.

 --log-file <file name>

    Log packet events to specified file. Note that this file grows
    indefinitely and may fill up the file system.

 --log-level <integer>

    Do not print message above log level.
    (ERROR: 1, WARN: 2, INFO: 3, DEBUG: 4)

 --log-packet

    Dump the start of each packet in hexadecimal into the log.    

Limitations:

 * TTL decrement and TTL checking are not implemented.

 * Packet sanity checks are generally not performed.

 * The log file feature does not implement any aging or clean-up.
   There is thus a risk for it to fill the file system.

 * This implementation is intended as a testing tool.

 * ARP does not age its entries.
