bounce - DPDK based tool for returning traffic to its source.

The source code is based on the DPDK l2fwd sample application with
minor changes.

Ethernet packets received are returned back to their source. The source MAC address is set to the port MAC address:

  tx.pkt.eth.dstmac = rx.pkt.eth.srcmac
  tx.pkt.eth.srdmac = port.mac

One can optionally specify the packet return rate. So instead of
returning every single packet one can specify to only return every
N'th packet with the '-r N' command line argument. All other packets
will be discarded.
