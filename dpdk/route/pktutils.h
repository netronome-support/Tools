#ifndef __RT_PKTUTILS_H__
#define __RT_PKTUTILS_H__

#include <string.h>

#include <rte_ethdev.h>
#include <rte_mbuf.h>

#include "defines.h"
#include "port.h"

#define PTR(ptr, type, offset) \
  ((type *) &(((char *) (ptr))[offset]))

extern struct rte_mempool *rt_pktmbuf_pool;

typedef struct {
    uint8_t dst[6];
    uint8_t src[6];
    uint16_t ethtype;
} __attribute__((packed)) rt_eth_hdr_t;

typedef struct {
    uint8_t     vershlen;
    uint8_t     TOS;
    uint16_t    length;
    uint16_t    ident;
    uint16_t    fraginfo;
    uint8_t     TTL;
    uint8_t     protocol;
    uint16_t    chksum;
    uint32_t    ipsa;
    uint32_t    ipda;
} __attribute__((packed)) rt_ipv4_hdr_t;

typedef struct {
    uint16_t    srcp;
    uint16_t    dstp;
    uint16_t    length;
    uint16_t    chksum;
} __attribute__((packed)) rt_udp_hdr_t;

typedef struct {
    uint8_t     type;
    uint8_t     code;
    uint16_t    chksum;
    uint16_t    ident;
    uint16_t    seq;
} __attribute__((packed)) rt_icmp_hdr_t;

typedef struct {
    struct rte_mbuf *mbuf;
    rt_port_info_t *pi; /* Receive Port */
    rt_rd_t rdidx; /* Routing Domain Index */
    rt_eth_hdr_t *eth;
    struct {
        void *l3;
    } pp;
} rt_pkt_t;

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
rt_pkt_send_fast (rt_pkt_t pkt, rt_port_index_t port, void *tx_buffer)
{
    assert(tx_buffer != NULL);
    assert(pkt.mbuf != NULL);
    rte_eth_tx_buffer(port, 0, tx_buffer, pkt.mbuf);
}

extern rt_eth_addr_t rt_eth_bcast_hw_addr;

void rt_pkt_create (rt_pkt_t *pkt);

void rt_pkt_send (rt_pkt_t pkt, rt_port_info_t *pi);

void rt_pkt_discard (rt_pkt_t pkt);

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

void rt_pkt_ipv4_setup (rt_pkt_t *pkt, uint8_t protocol,
    rt_ipv4_addr_t ipsa, rt_ipv4_addr_t ipda);

void rt_pkt_udp_setup (rt_udp_hdr_t *udp, int payload_length,
    uint16_t srcp, uint16_t dstp);

void rt_pkt_ipv4_calc_chksum (rt_ipv4_hdr_t *ip);
void rt_pkt_udp_calc_chksum (rt_ipv4_hdr_t *ip);

uint16_t rt_pkt_chksum (const void *buf, int len, uint32_t cs);

#endif
