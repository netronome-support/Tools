#include <stdlib.h>

#include "defines.h"
#include "pktutils.h"
#include "dbgmsg.h"

#include <rte_ethdev.h>

rt_eth_addr_t rt_eth_bcast_hw_addr
    = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };

void
rt_pkt_send (rt_pkt_t pkt, rt_port_info_t *pi)
{
    //dbgmsg(INFO, pkt, "rt_pkt_send");
    rt_port_index_t port = pi->idx;
    struct rte_eth_dev_tx_buffer *buffer = pi->tx_buffer;
    if (!(pi->flags & RT_PORT_F_EXIST)) {
        dbgmsg(WARN, pkt, "port not active (%u)", pi->idx);
        rt_pkt_discard(pkt);
        return;
    }
    assert(pkt.rdidx != 0);
    assert(buffer != NULL);
    assert(pkt.mbuf != NULL);
    rte_eth_tx_buffer(port, 0, buffer, pkt.mbuf);
}

void
rt_pkt_discard (rt_pkt_t pkt)
{
    assert(pkt.mbuf != NULL);
    rte_pktmbuf_free(pkt.mbuf);
    pkt.mbuf = NULL;
}

void
rt_pkt_create (rt_pkt_t *pkt)
{
    /* Allocate mbuf */
    assert(rt_pktmbuf_pool != NULL);
    pkt->mbuf = rte_pktmbuf_alloc(rt_pktmbuf_pool);
    assert(pkt->mbuf != NULL);
    pkt->eth = rte_pktmbuf_mtod(pkt->mbuf, void *);
}

void
rt_pkt_ipv4_setup (rt_pkt_t *pkt, uint8_t protocol,
    rt_ipv4_addr_t ipsa, rt_ipv4_addr_t ipda)
{
    /* Set ETHTYPE to IPv4 */
    *PTR(pkt->eth, uint16_t, 12) = htons(0x0800);
    pkt->pp.l3 = &((uint8_t *) pkt->eth)[14];
    rt_ipv4_hdr_t *ip = pkt->pp.l3;
    memset(ip, 0, sizeof(rt_ipv4_hdr_t));
    ip->vershlen = 0x45;
    ip->length = 20;
    ip->TTL = 64;
    ip->protocol = protocol;
    ip->ipsa = htonl(ipsa);
    ip->ipda = htonl(ipda);
}

void
rt_pkt_ipv4_calc_chksum (rt_ipv4_hdr_t *ip)
{
    int iphl = (ip->vershlen & 0x0f) * 4;
    ip->chksum = 0;
    ip->chksum = ~ htons(rt_pkt_chksum(ip, iphl, 0));
}

void
rt_pkt_udp_setup (rt_udp_hdr_t *udp, int payload_length,
    uint16_t srcp, uint16_t dstp)
{
    udp->srcp = htons(srcp);
    udp->dstp = htons(dstp);
    udp->length = htons(payload_length);
    udp->chksum = 0;
}

void
rt_pkt_udp_calc_chksum (rt_ipv4_hdr_t *ip)
{
    int iphl = (ip->vershlen & 0x0f) * 4;
    rt_udp_hdr_t *udp = PTR(ip, rt_udp_hdr_t, iphl);
    int udplen = ntohs(udp->length);
    uint32_t cs = 0;
    /* UDP pseudo-header */
    cs = rt_pkt_chksum(PTR(ip, void, 12), 8, cs);
    uint16_t psuedo = htons(ip->protocol);
    cs = rt_pkt_chksum(&psuedo, 2, cs);
    cs = rt_pkt_chksum(&udp->length, 2, cs);
    /* UDP Header and Payload */
    udp->chksum = 0;
    cs = rt_pkt_chksum(udp, udplen, cs);
    udp->chksum = htons(~ cs);
}

uint16_t
rt_pkt_chksum (const void *buf, int len, uint32_t cs) {
    int i;
    const uint8_t *msg = buf;
    for (i = 0 ; i < len ; i++)
        cs += (1 & i) ? msg[i] : (msg[i] << 8);
    while ((cs >> 16) != 0)
        cs = (cs & 0xFFFF) + (cs >> 16);
    return cs;
}
