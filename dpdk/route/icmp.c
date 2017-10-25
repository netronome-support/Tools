#include "defines.h"
#include "stats.h"
#include "pktutils.h"
#include "tables.h"
#include "dbgmsg.h"
#include "functions.h"

static inline void
rt_icmp_set_chksum (void *p, int len)
{
    rt_icmp_hdr_t *icmp = (rt_icmp_hdr_t *) p;
    icmp->chksum = 0;
    uint16_t chksum = ~ rt_pkt_chksum(icmp, len, 0);
    icmp->chksum = htons(chksum);
}

static inline void
rt_icmp_request (rt_pkt_t pkt, void *icmp)
{
    /* Set ICMP type to ECHO REPLY */
    *PTR(icmp, uint8_t, 0) = 0;

    /* Check on packet length */
    int buflen = rt_pkt_length(pkt);
    uint16_t iplen = ntohs(*PTR(pkt.pp.l3, uint16_t, 2));
    uint16_t icmplen = iplen - 20;
    if (buflen < (iplen + 14)) {
        rt_pkt_discard(pkt);
        return;
    }

    /* Update ICMP checksum */
    rt_icmp_set_chksum(icmp, icmplen);

    /* Reverse IP addresses */
    rt_ipv4_addr_t ripa = *PTR(pkt.pp.l3, rt_ipv4_addr_t, 12);
    rt_ipv4_addr_t lipa = *PTR(pkt.pp.l3, rt_ipv4_addr_t, 16);
    *PTR(pkt.pp.l3, rt_ipv4_addr_t, 12) = lipa;
    *PTR(pkt.pp.l3, rt_ipv4_addr_t, 16) = ripa;

    char t0[32], t1[32];
    dbgmsg(INFO, nopkt, "ICMP Echo Request/Response"
        " (local: (%u) %s ; remote %s)", pkt.rdidx,
        rt_ipaddr_str(t0, ntohl(lipa)),
        rt_ipaddr_str(t1, ntohl(ripa)));

    rt_pkt_ipv4_send(pkt, ntohl(ripa), 0);
}

static void
rt_icmp_proc_reply (rt_pkt_t pkt, __attribute__((unused)) void *icmp)
{
    char t0[32], t1[32];
    rt_ipv4_addr_t ipsa = ntohl(*PTR(pkt.pp.l3, uint32_t, 12));
    rt_ipv4_addr_t ipda = ntohl(*PTR(pkt.pp.l3, uint32_t, 16));
    dbgmsg(INFO, pkt, "ICMP Reply from (%u) %s to local address %s",
        pkt.rdidx,
        rt_ipaddr_str(t0, ipsa),
        rt_ipaddr_str(t1, ipda));
    rt_pkt_discard(pkt);
    return;
}

void rt_icmp_gen_request (rt_rd_t rdidx, rt_ipv4_addr_t ipda)
{
    static uint16_t ping_seq = 1;
    /* Create new packet for ARP request */
    rt_pkt_t pkt;
    rt_pkt_create(&pkt);
    pkt.pi = NULL;
    pkt.rdidx = rdidx;

    /* Set ETHTYPE to IPv4 */
    pkt.eth->ethtype = htons(0x0800);
    pkt.pp.l3 = &((uint8_t *) pkt.eth)[14];

    rt_ipv4_hdr_t *ip = (rt_ipv4_hdr_t *) pkt.pp.l3;
    memset(ip, 0, 28);
    ip->vershlen = 0x45;
    ip->length = htons(20 + 8); /* IP header + ICMP header */
    ip->TTL = 64;
    ip->protocol = 1; /* ICMP */
    ip->ipda = htonl(ipda);
    /* IPSA and checksum will updated in rt_pkt_ipv4_send */

    rt_icmp_hdr_t *icmp = (rt_icmp_hdr_t *) &ip[1];
    icmp->type = 8; /* ICMP echo request */
    icmp->code = 0;
    icmp->ident = htons(0xfee1);
    icmp->seq = htons(ping_seq++);
    rt_icmp_set_chksum(icmp, 8);

    dbgmsg(INFO, pkt, "ICMP generate request for (%u) %s",
        pkt.rdidx, rt_ipaddr_nr_str(ipda));

    rt_pkt_set_length(pkt, 14 + 20 + 8);
    rt_pkt_ipv4_send(pkt, ipda, PKT_SEND_F_UPDATE_IPSA);
}

void rt_icmp_process (rt_pkt_t pkt)
{
    void *icmp = PTR(pkt.pp.l3, void, 20);
    uint8_t type = *PTR(icmp, uint8_t, 0);
    //uint8_t code = *PTR(icmp, uint8_t, 1);
    if (type == 8) {
        rt_icmp_request(pkt, icmp);
        return;
    }
    if (type == 0) {
        rt_icmp_proc_reply(pkt, icmp);
        return;
    }
    dbgmsg(DEBUG, pkt, "ICMP ignoring packet");
    rt_pkt_discard(pkt);
}
