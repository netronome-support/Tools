#ifndef __RT_FUNCTIONS_H__
#define __RT_FUNCTIONS_H__

#include "defines.h"
#include "pktutils.h"
#include "tables.h"

void rt_pkt_process (int port, struct rte_mbuf *m);
void rt_pkt_ipv4_send (rt_pkt_t pkt, rt_ipv4_addr_t ipda);

void rt_arp_process (rt_pkt_t pkt);
void rt_arp_generate (rt_pkt_t pkt, rt_ipv4_addr_t ipda, rt_lpm_t *rt);

void rt_icmp_process (rt_pkt_t pkt);

void rt_dhcp_process (rt_pkt_t pkt);
void rt_dhcp_discover (void);

int parse_iface_addr (const char *arg);
int parse_ipv4_route (const char *arg);

#endif
