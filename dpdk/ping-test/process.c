#include <stdint.h>

#include "defines.h"
#include "pktutils.h"
#include "functions.h"
#include "dbgmsg.h"

void
pkt_ipv4_send (pkt_t pkt, ipv4_addr_t ipda)
{
    if (!g.have_hwaddr) {
        arp_generate(pkt, ipda);
        return;
    }

    pkt_ipv4_calc_chksum(pkt.pp.l3);

    port_info_t *pi = port_lookup(g.prtidx);

    memcpy(PTR(pkt.eth, void, 0), g.r_hwaddr, 6);
    memcpy(PTR(pkt.eth, void, 6), pi->hwaddr, 6);

    pkt_send(pkt, g.prtidx);
}

void
pkt_process (__attribute__((unused)) int prtidx,
    struct rte_mbuf *mbuf, uint32_t tsc)
{
    pkt_t pkt;
    pkt.mbuf = mbuf;
    pkt.eth = rte_pktmbuf_mtod(mbuf, void *);
    pkt.r_tsc = tsc;

    uint16_t ethtype = ntohs(pkt.eth->ethtype);

    /* Look-up in Direct (fast) Table */
    if (likely(ethtype == 0x0800)) {
        pkt.pp.l3 = PTR(pkt.eth, void, 14);
        ipv4_addr_t ipsa = ntohl(*PTR(pkt.pp.l3, uint32_t, 12));
        ipv4_addr_t ipda = ntohl(*PTR(pkt.pp.l3, uint32_t, 16));
        uint8_t proto = *PTR(pkt.pp.l3, uint8_t, 9);
        if (ipsa != g.r_ipv4_addr) {
            goto Discard;
        }
        if (ipda != g.l_ipv4_addr) {
            goto Discard;
        }
        if (proto != 1) {
            goto Discard;
        }
        icmp_process(pkt);
        return;
    }

    if (ethtype == 0x0806) {
        pkt.pp.l3 = PTR(pkt.eth, void, 14);
        arp_process(pkt);
        return;
    }

  Discard:
    rte_pktmbuf_free(pkt.mbuf);
}
