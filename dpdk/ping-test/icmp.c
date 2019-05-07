#include "defines.h"
#include "pktutils.h"
#include "dbgmsg.h"
#include "functions.h"

#include <rte_cycles.h>

void
icmp_print_stats (void)
{
    #define FMT "%-24s  %14lu\n"
    printf(FMT, "[TX] Transmitted:",    icmp_stats.tx_pkt_cnt);
    printf(FMT, "[RX] Received:",       icmp_stats.rx_pkt_cnt);
    printf(FMT, "[LT] Lost:",           icmp_stats.tx_pkt_cnt
                                      - icmp_stats.rx_pkt_cnt);
    printf(FMT, "[OO] Out-of-order:",   icmp_stats.out_of_order);
    printf("\n");
}

static inline void
icmp_set_chksum (void *p, int len)
{
    icmp_hdr_t *icmp = (icmp_hdr_t *) p;
    icmp->chksum = 0;
    uint16_t chksum = ~ pkt_chksum(icmp, len, 0);
    icmp->chksum = htons(chksum);
}

static inline void
icmp_request (pkt_t pkt, void *icmp)
{
    /* Set ICMP type to ECHO REPLY */
    *PTR(icmp, uint8_t, 0) = 0;

    /* Check on packet length */
    int buflen = pkt_length(pkt);
    uint16_t iplen = ntohs(*PTR(pkt.pp.l3, uint16_t, 2));
    uint16_t icmplen = iplen - 20;
    if (buflen < (iplen + 14)) {
        dbgmsg(WARN, pkt, "ICMP Packet too small");
        pkt_discard(pkt);
        return;
    }

    /* Update ICMP checksum */
    icmp_set_chksum(icmp, icmplen);

    /* Reverse IP addresses */
    ipv4_addr_t ripa = *PTR(pkt.pp.l3, ipv4_addr_t, 12);
    ipv4_addr_t lipa = *PTR(pkt.pp.l3, ipv4_addr_t, 16);
    *PTR(pkt.pp.l3, ipv4_addr_t, 12) = lipa;
    *PTR(pkt.pp.l3, ipv4_addr_t, 16) = ripa;

    char t0[32], t1[32];
    dbgmsg(INFO, nopkt, "ICMP Echo Request/Response"
        " (local: %s ; remote %s)",
        ipaddr_str(t0, ntohl(lipa)),
        ipaddr_str(t1, ntohl(ripa)));

    pkt_ipv4_send(pkt, ntohl(ripa));
}

static inline void
icmp_process_sequence_number (uint16_t rsn)
{
    uint16_t esn = icmp_stats.rx_seq_num + 1; /* Expected SN */
    int16_t diff = (int16_t) (esn - rsn);
    if (unlikely(diff != 0)) {
        icmp_stats.out_of_order++;
    }
    icmp_stats.rx_seq_num = rsn;
}

static void
icmp_proc_reply (pkt_t pkt, __attribute__((unused)) void *icmp)
{
    ipv4_addr_t ipsa = ntohl(*PTR(pkt.pp.l3, uint32_t, 12));
    ipv4_addr_t ipda = ntohl(*PTR(pkt.pp.l3, uint32_t, 16));
    char t0[32], t1[32];
    dbgmsg(DEBUG, pkt, "ICMP Reply from %s to local address %s",
        ipaddr_str(t0, ipsa),
        ipaddr_str(t1, ipda));

    uint32_t t_tsc = ntohl(*PTR(pkt.pp.l3, uint32_t, 28));
    uint32_t diff = pkt.r_tsc - t_tsc;
    latency_save(diff);
    icmp_process_sequence_number(ntohs(((icmp_hdr_t *) icmp)->seq));
    pkt_discard(pkt);
    icmp_stats.rx_pkt_cnt++;
    return;
}

void icmp_gen_request (ipv4_addr_t ipda)
{
    int pktsize = g.pktsize;
    /* Create new packet for ARP request */
    pkt_t pkt;
    pkt_create(&pkt);

    pkt_set_length(pkt, g.pktsize);

    /* Set ETHTYPE to IPv4 */
    pkt.eth->ethtype = htons(0x0800);
    pkt.pp.l3 = &((uint8_t *) pkt.eth)[14];
    pktsize -= 14;

    ipv4_hdr_t *ip = (ipv4_hdr_t *) pkt.pp.l3;
    memset(ip, 0, pktsize);
    ip->vershlen = 0x45;
    ip->length = htons(pktsize);
    ip->TTL = 64;
    ip->protocol = 1; /* ICMP */
    ip->ipda = htonl(ipda);
    ip->ipsa = htonl(g.l_ipv4_addr);
    pktsize -= 20;

    icmp_hdr_t *icmp = (icmp_hdr_t *) &ip[1];
    icmp->type = 8; /* ICMP echo request */
    icmp->code = 0;
    icmp->ident = htons(0xfee1);
    icmp->seq = htons(++icmp_stats.tx_seq_num);

    /* Set ICMP Ping time-stamp in payload */
    ((uint32_t *) icmp)[2] = htonl(rte_rdtsc());

    icmp_set_chksum(icmp, pktsize);

    pkt_ipv4_send(pkt, ipda);

    icmp_stats.tx_pkt_cnt++;
}

void icmp_process (pkt_t pkt)
{
    void *icmp = PTR(pkt.pp.l3, void, 20);
    uint8_t type = *PTR(icmp, uint8_t, 0);
    if (type == 8) {
        icmp_request(pkt, icmp);
        return;
    }
    if (type == 0) {
        icmp_proc_reply(pkt, icmp);
        return;
    }
    dbgmsg(DEBUG, pkt, "ICMP type (=%d) not processed", type);
    pkt_discard(pkt);
}
