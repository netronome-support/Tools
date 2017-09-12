#include <stdint.h>

#include "defines.h"
#include "stats.h"
#include "pktutils.h"
#include "tables.h"
#include "functions.h"
#include "dbgmsg.h"

static inline void
rt_pkt_ipv4_local_process (rt_pkt_t pkt)
{
    uint8_t proto = *PTR(pkt.pp.l3, uint8_t, 9);
    void *pp_l4 = PTR(pkt.pp.l3, void, 20);
    if (proto == 1) { /* ICMP */
        rt_icmp_process(pkt);
        return;
    }
    if (proto == 17) { /* UDP */
        uint16_t udp_dst_port = ntohs(*PTR(pp_l4, uint16_t, 2));
        if (udp_dst_port == 68) { /* BOOTP */
            rt_dhcp_process(pkt);
            return;
        }
    }

    char t0[32], t1[32];
    dbgmsg(WARN, pkt, "IPv4 LOCAL ignored"
        " (local: (%u) %s ; remote: %s ; protocol %u)",
        pkt.pi->rdidx,
        rt_ipaddr_str(t0, ntohl(*PTR(pkt.pp.l3, uint32_t, 16))),
        rt_ipaddr_str(t1, ntohl(*PTR(pkt.pp.l3, uint32_t, 12))),
        proto);

    rt_pkt_discard(pkt);
}

static inline void
rt_pkt_nh_resolve (rt_pkt_t pkt, rt_lpm_t *rt, rt_ipv4_addr_t ipda)
{
    const char *errmsg;
    /* Lookup route for the NextHop */
    rt_lpm_t *nhr = rt_lpm_lookup(pkt.pi->rdidx, rt->nhipa);
    if (nhr == NULL) {
        errmsg = "no route for next-hop address";
        goto NextHopError;
    }

    uint32_t nh_flags = nhr->flags;
    if (nh_flags & RT_LPM_F_LOCAL) {
        errmsg = "next-hop points at local address";
        goto NextHopError;
    }
    if ((nh_flags & RT_LPM_F_HAS_NEXTHOP) || (nhr->nh != NULL)) {
        errmsg = "nested next-hops not supported";
        goto NextHopError;
    }
    if (!(nh_flags & RT_LPM_F_HAS_PORTINFO)) {
        errmsg = "next-hop missing port-info";
        goto NextHopError;
    }

    if (!rt_lpm_is_host_route(nhr)) {
        /* Create (or find) host route */
        rt_ipv4_prefix_t prefix;
        prefix.addr = rt->nhipa;
        prefix.len = 32;
        nhr = rt_lpm_find_or_create(pkt.pi->rdidx, prefix, nhr->pi);
        nh_flags = nhr->flags;
    }

    /* Set the Next Hop of the route */
    rt->nh = nhr;

    if (!(nh_flags & RT_LPM_F_HAS_HWADDR)) {
        rt_arp_generate(pkt, rt->nhipa, nhr);
        return;
    }

    dbgmsg(INFO, pkt, "forwarding - next-hop already resolved");

    /* All information available. Create DT entry */
    rt_dt_create(nhr, ipda);

    /* Update MAC addresses */
    rt_pkt_set_hw_addrs(pkt, nhr->pi, nhr->hwaddr);
    /* Send Packet */
    rt_pkt_send(pkt, nhr->pi);

    return;

  NextHopError:
    dbgmsg(WARN, pkt, "%s (%u) %s", errmsg, pkt.pi->rdidx,
        rt_ipaddr_nr_str(rt->nhipa));
    rt_pkt_discard(pkt);

}

void
rt_pkt_ipv4_send (rt_pkt_t pkt, rt_ipv4_addr_t ipda)
{
    rt_lpm_t *rt = rt_lpm_lookup(pkt.pi->rdidx, ipda);
    if (rt == NULL) {
        /* No Route - Discard */
        dbgmsg(WARN, pkt, "IPv4 NO ROUTE for (%u) %s",
            pkt.pi->rdidx, rt_ipaddr_nr_str(ipda));
        rt_stats_incr(1);
        rt_pkt_discard(pkt);
        return;
    }

    uint32_t flags = rt->flags;
    rt_ipv4_addr_t nhipa = ipda;

    if (flags & RT_LPM_F_LOCAL) {
        rt_pkt_ipv4_local_process(pkt);
        return;
    }

    if (rt->nh != NULL) {
        rt = rt->nh;
        flags = rt->flags;
        nhipa = rt->prefix.addr;
    } else
    if (flags & RT_LPM_F_HAS_NEXTHOP) {
        nhipa = rt->nhipa;
        if (!(rt->flags & RT_LPM_F_HAS_HWADDR)) {
            rt_pkt_nh_resolve(pkt, rt, ipda);
            return;
        }
    }

    if (flags & RT_LPM_F_HAS_HWADDR) {
        /* Add a Direct Table entry */
        rt_dt_create(rt, ipda);
        /* Update MAC addresses and send */
        rt_pkt_set_hw_addrs(pkt, rt->pi, rt->hwaddr);
        rt_pkt_send(pkt, rt->pi);
    } else {
        rt_arp_generate(pkt, nhipa, rt);
    }
}

static inline void
rt_pkt_ipv4_process (rt_pkt_t pkt)
{
    rt_ipv4_addr_t ipda = ntohl(*PTR(pkt.pp.l3, uint32_t, 16));
    /* Look-up in Direct (fast) Table */
    rt_dt_route_t *drp = rt_dt_lookup(pkt.pi->rdidx, ipda);
    if (drp != NULL) {
        /* Update MAC addresses */
        memcpy(&pkt.eth->dst, drp->eth.dst, 6);
        memcpy(&pkt.eth->src, &drp->eth.src, 6);
        /* Send Packet */
        rt_pkt_send_fast(pkt, drp->port, drp->tx_buffer);
        return;
    }

    if ((ipda >> 28) == 0xf) {
        /* Multicast */
        rt_pkt_ipv4_local_process(pkt);
        return;
    }

    dbgmsg(WARN, pkt, "IPv4 Slow Path");

    rt_pkt_ipv4_send(pkt, ipda);
}

void
rt_pkt_process (int port, struct rte_mbuf *mbuf)
{
    rt_pkt_t pkt;
    pkt.pi = rt_port_lookup(port);
    pkt.mbuf = mbuf;
    pkt.eth = rte_pktmbuf_mtod(mbuf, void *);

    uint16_t ethtype = ntohs(pkt.eth->ethtype);

    pkt.pp.l3 = PTR(pkt.eth, void, 14);

    /* Compare Destination MAC address */
    if (rt_eth_addr_compare(&pkt.eth->dst, &pkt.pi->hwaddr)) {
        /* Check for IPv4 */
        if (ethtype == 0x0800) {
            rt_pkt_ipv4_process(pkt);
            return;
        } else
        if (ethtype == 0x0806) {
            rt_arp_process(pkt);
            return;
        }
        //dbgmsg(WARN, pkt, "unsupported ETHTYPE");
    } else
    if (pkt.eth->dst[0] & 1) { /* Broadcast or Multicast */
        if (ethtype == 0x0800) {
            rt_pkt_ipv4_process(pkt);
            return;
        } else
        if (ethtype == 0x0806) {
            rt_arp_process(pkt);
            return;
        }
        rt_stats_incr(1);
        //dbgmsg(WARN, pkt, "unsupported ETHTYPE (multicast)");
    } else {
        rt_stats_incr(1);
        dbgmsg(WARN, pkt, "wrong destination MAC");
    }
    rt_pkt_discard(pkt);
}
