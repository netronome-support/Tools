#ifndef __RT_FUNCTIONS_H__
#define __RT_FUNCTIONS_H__

#include "defines.h"
#include "pktutils.h"
#include "tables.h"

void rt_pkt_process (int port, struct rte_mbuf *m);

void rt_pkt_setup_dt (rt_port_info_t *i_pi, rt_ipv4_addr_t ipda,
    rt_lpm_t *rt, rt_ipv4_ar_t *ar);

void rt_pkt_ipv4_send (rt_pkt_t pkt, rt_ipv4_addr_t ipda, int flags);
#define PKT_SEND_F_UPDATE_IPSA          (1 << 0)

void rt_arp_process (rt_pkt_t pkt);
void rt_arp_generate (rt_pkt_t pkt, rt_ipv4_addr_t ipda, rt_lpm_t *rt);
void rt_arp_send_gratuitous (rt_port_info_t *pi);

void rt_icmp_process (rt_pkt_t pkt);
void rt_icmp_gen_request (rt_rd_t rdidx, rt_ipv4_addr_t ipda);

void rt_dhcp_process (rt_pkt_t pkt);
void rt_dhcp_discover (void);

int parse_iface_addr (const char *arg);
int parse_ipv4_route (const char *arg);
int port_set_promisc_flag (const char *arg);
int add_static_arp_entry (const char *arg);
int parse_port_pinning (const char *arg);
int parse_add_iface_addr (const char *arg);

#endif
