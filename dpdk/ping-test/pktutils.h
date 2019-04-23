#ifndef __RT_PKTUTILS_H__
#define __RT_PKTUTILS_H__

#include <string.h>
#include <stdbool.h>

#include <rte_ethdev.h>
#include <rte_mbuf.h>

#include "defines.h"
#include "port.h"
#include "pktdefs.h"

#define PTR(ptr, type, offset) \
  ((type *) &(((char *) (ptr))[offset]))

extern struct rte_mempool *pktmbuf_pool;

static inline void
pkt_set_hw_addrs (pkt_t pkt, void *hw_dst_addr)
{
    memcpy(PTR(pkt.eth, void, 0), hw_dst_addr, 6);
    port_info_t *pi = port_lookup(g.prtidx);
    memcpy(PTR(pkt.eth, void, 6), pi->hwaddr, 6);
}

static inline int
eth_addr_compare (eth_addr_t *a, eth_addr_t *b)
{
    register uint64_t r_a = *((uint64_t *) a);
    register uint64_t r_b = *((uint64_t *) b);
    return ((r_a ^ r_b) & 0xffffff) == 0;
}

extern eth_addr_t eth_bcast_hw_addr;

void pkt_create (pkt_t *pkt);

void pkt_send (pkt_t pkt, port_index_t prtidx);

/*
 * Discard and update 'discard reason' counter
 */
static inline void
pkt_discard (pkt_t pkt)
{
    assert(pkt.mbuf != NULL);
    rte_pktmbuf_free(pkt.mbuf);
}

static inline int
pkt_length (pkt_t pkt)
{
    return rte_pktmbuf_pkt_len(pkt.mbuf);
}

static inline void
pkt_set_length (pkt_t pkt, int length)
{
    pkt.mbuf->pkt_len = length;
    pkt.mbuf->data_len = length;
}

static inline bool
pkt_is_unicast (pkt_t pkt)
{
    return ((pkt.eth->dst[0] & 1) == 0);
}

void pkt_ipv4_setup (pkt_t *pkt, uint8_t protocol,
    ipv4_addr_t ipsa, ipv4_addr_t ipda);

void pkt_udp_setup (udp_hdr_t *udp, int payload_length,
    uint16_t srcp, uint16_t dstp);

void pkt_ipv4_calc_chksum (ipv4_hdr_t *ip);
void pkt_udp_calc_chksum (ipv4_hdr_t *ip);

uint16_t pkt_chksum (const void *buf, int len, uint32_t cs);

#endif
