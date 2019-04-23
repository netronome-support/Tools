#include <stdlib.h>

#include "defines.h"
#include "pktutils.h"
#include "dbgmsg.h"

#include <rte_ethdev.h>

eth_addr_t eth_bcast_hw_addr
    = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };

void
pkt_send (pkt_t pkt, port_index_t prtidx)
{
    assert(pkt.mbuf != NULL);
    port_info_t *pi = port_lookup(prtidx);
    rte_eth_tx_buffer(prtidx, 0, pi->tx_buffer, pkt.mbuf);
}

void
pkt_create (pkt_t *pkt)
{
    /* Allocate mbuf */
    assert(pktmbuf_pool != NULL);
    pkt->mbuf = rte_pktmbuf_alloc(pktmbuf_pool);
    assert(pkt->mbuf != NULL);
    pkt->eth = rte_pktmbuf_mtod(pkt->mbuf, void *);
}

void
pkt_ipv4_setup (pkt_t *pkt, uint8_t protocol,
    ipv4_addr_t ipsa, ipv4_addr_t ipda)
{
    /* Set ETHTYPE to IPv4 */
    *PTR(pkt->eth, uint16_t, 12) = htons(0x0800);
    pkt->pp.l3 = &((uint8_t *) pkt->eth)[14];
    ipv4_hdr_t *ip = pkt->pp.l3;
    memset(ip, 0, sizeof(ipv4_hdr_t));
    ip->vershlen = 0x45;
    ip->length = 20;
    ip->TTL = 64;
    ip->protocol = protocol;
    ip->ipsa = htonl(ipsa);
    ip->ipda = htonl(ipda);
}

void
pkt_ipv4_calc_chksum (ipv4_hdr_t *ip)
{
    int iphl = (ip->vershlen & 0x0f) * 4;
    ip->chksum = 0;
    ip->chksum = ~ htons(pkt_chksum(ip, iphl, 0));
}

uint16_t
pkt_chksum (const void *buf, int len, uint32_t cs) {
    int i;
    const uint8_t *msg = buf;
    for (i = 0 ; i < len ; i++)
        cs += (1 & i) ? msg[i] : (msg[i] << 8);
    while ((cs >> 16) != 0)
        cs = (cs & 0xFFFF) + (cs >> 16);
    return cs;
}
