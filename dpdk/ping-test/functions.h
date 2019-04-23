#ifndef __RT_FUNCTIONS_H__
#define __RT_FUNCTIONS_H__

#include <stdint.h>

#include "defines.h"
#include "pktutils.h"

void pkt_ipv4_send (pkt_t pkt, ipv4_addr_t ipda);

void arp_process (pkt_t pkt);
void arp_generate (pkt_t pkt, ipv4_addr_t ipda);

void icmp_process (pkt_t pkt);
void icmp_gen_request (ipv4_addr_t ipda);

int parse_args (int argc, char **argv);

void latency_setup (void);
void latency_save (uint32_t tsc);
int latency_print (void);
int latency_dump (const char *fname);

void pkt_process (int prtidx, struct rte_mbuf *mbuf, uint32_t tsc);
void main_loop (void);

#endif
