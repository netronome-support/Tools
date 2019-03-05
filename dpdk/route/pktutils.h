#ifndef __RT_PKTUTILS_H__
#define __RT_PKTUTILS_H__

#include <string.h>
#include <stdbool.h>

#include <rte_ethdev.h>
#include <rte_mbuf.h>

#include "defines.h"
#include "port.h"
#include "pktdefs.h"
#include "rings.h"

#define PTR(ptr, type, offset) \
  ((type *) &(((char *) (ptr))[offset]))

extern struct rte_mempool *rt_pktmbuf_pool;

static inline void
rt_pkt_set_hw_addrs (rt_pkt_t pkt, rt_port_info_t *pi, void *hw_dst_addr)
{
    memcpy(PTR(pkt.eth, void, 0), hw_dst_addr, 6);
    memcpy(PTR(pkt.eth, void, 6), pi->hwaddr, 6);
}

static inline int
rt_eth_addr_compare (rt_eth_addr_t *a, rt_eth_addr_t *b)
{
    register uint64_t r_a = *((uint64_t *) a);
    register uint64_t r_b = *((uint64_t *) b);
    return ((r_a ^ r_b) & 0xffffff) == 0;
}

static inline void
rt_pkt_send_fast (rt_pkt_t pkt, rt_port_index_t port)
{
    assert(pkt.mbuf != NULL);
    tx_pkt_enqueue(port, pkt.mbuf);
}

extern rt_eth_addr_t rt_eth_bcast_hw_addr;

void rt_pkt_create (rt_pkt_t *pkt);

void rt_pkt_send (rt_pkt_t pkt, rt_port_info_t *pi);

/*
 * Discard and update DISC counter
 */
static inline void
rt_pkt_discard (rt_pkt_t pkt)
{
    assert(pkt.mbuf != NULL);
    rte_pktmbuf_free(pkt.mbuf);
    pkt.mbuf = NULL;
    if (pkt.pi != NULL) {
        port_statistics[pkt.pi->idx].disc++;
    }
}

/*
 * Discard and update ERROR counter
 */
static inline void
rt_pkt_discard_error (rt_pkt_t pkt)
{
    assert(pkt.mbuf != NULL);
    rte_pktmbuf_free(pkt.mbuf);
    pkt.mbuf = NULL;
    if (pkt.pi != NULL) {
        port_statistics[pkt.pi->idx].error++;
    }
}

/*
 * Discard and update TERM counter
 */
static inline void
rt_pkt_terminate (rt_pkt_t pkt)
{
    assert(pkt.mbuf != NULL);
    rte_pktmbuf_free(pkt.mbuf);
    pkt.mbuf = NULL;
    if (pkt.pi != NULL) {
        port_statistics[pkt.pi->idx].term++;
    }
}

static inline int
rt_pkt_length (rt_pkt_t pkt)
{
    return rte_pktmbuf_pkt_len(pkt.mbuf);
}

static inline void
rt_pkt_set_length (rt_pkt_t pkt, int length)
{
    pkt.mbuf->pkt_len = length;
    pkt.mbuf->data_len = length;
}

static inline bool
rt_pkt_is_unicast (rt_pkt_t pkt)
{
    return ((pkt.eth->dst[0] & 1) == 0);
}

void rt_pkt_ipv4_setup (rt_pkt_t *pkt, uint8_t protocol,
    rt_ipv4_addr_t ipsa, rt_ipv4_addr_t ipda);

void rt_pkt_udp_setup (rt_udp_hdr_t *udp, int payload_length,
    uint16_t srcp, uint16_t dstp);

void rt_pkt_ipv4_calc_chksum (rt_ipv4_hdr_t *ip);
void rt_pkt_udp_calc_chksum (rt_ipv4_hdr_t *ip);

uint16_t rt_pkt_chksum (const void *buf, int len, uint32_t cs);

#endif
