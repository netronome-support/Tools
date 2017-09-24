#include "defines.h"
#include "stats.h"
#include "pktutils.h"
#include "tables.h"
#include "dbgmsg.h"
#include "functions.h"

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
    *PTR(icmp, uint16_t, 2) = 0;
    uint16_t chksum = ~ rt_pkt_chksum(icmp, icmplen, 0);
    *PTR(icmp, uint16_t, 2) = htons(chksum);

    /* Reverse IP addresses */
    rt_ipv4_addr_t ripa = *PTR(pkt.pp.l3, rt_ipv4_addr_t, 12);
    rt_ipv4_addr_t lipa = *PTR(pkt.pp.l3, rt_ipv4_addr_t, 16);
    *PTR(pkt.pp.l3, rt_ipv4_addr_t, 12) = lipa;
    *PTR(pkt.pp.l3, rt_ipv4_addr_t, 16) = ripa;

    char t0[32], t1[32];
    dbgmsg(INFO, nopkt, "ICMP Echo Request/Response"
        " (local: (%u) %s ; remote %s)", pkt.pi->rdidx,
        rt_ipaddr_str(t0, ntohl(lipa)),
        rt_ipaddr_str(t1, ntohl(ripa)));

    rt_pkt_ipv4_send(pkt, ntohl(ripa));
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
    dbgmsg(INFO, pkt, "ICMP ignoring packet");
    rt_pkt_discard(pkt);
}
