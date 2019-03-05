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
        pkt.rdidx,
        rt_ipaddr_str(t0, ntohl(*PTR(pkt.pp.l3, uint32_t, 16))),
        rt_ipaddr_str(t1, ntohl(*PTR(pkt.pp.l3, uint32_t, 12))),
        proto);

    rt_pkt_terminate(pkt);
}

void
rt_pkt_setup_dt (rt_port_info_t *i_pi, rt_ipv4_addr_t ipda,
    rt_lpm_t *rt, rt_ipv4_ar_t *ar)
{
    /* Egress Port Info */
    rt_port_info_t *e_pi = rt->pi;
    /* Create Direct-Table Entry */
    rt_dt_route_t dt;
    memset(&dt, 0, sizeof(dt));
    dt.key.prtidx = i_pi->idx;
    dt.key.ipaddr = ipda;
    dt.pi = e_pi;
    dt.port = e_pi->idx;
    dt.flags = rt->flags & RT_FWD_F_MASK;
    dt.tx_buffer = e_pi->tx_buffer;
    memcpy(dt.key.hwaddr, i_pi->hwaddr, 6);
    if (ar != NULL) {
        memcpy(dt.eth.dst, ar->hwaddr, 6);
    }
    memcpy(dt.eth.src, e_pi->hwaddr, 6);
    rt_dt_create(&dt);
}

void
rt_pkt_ipv4_send (rt_pkt_t pkt, rt_ipv4_addr_t ipda, int flags)
{
    rt_rd_t rdidx = pkt.rdidx;
    rt_lpm_t *rt = rt_lpm_lookup(rdidx, ipda);
    if (rt == NULL) {
        /* No Route - Discard */
        dbgmsg(WARN, pkt, "IPv4 NO ROUTE for (%u) %s",
            rdidx, rt_ipaddr_nr_str(ipda));
        rt_pkt_discard_error(pkt);
        return;
    }

    uint32_t rt_flags = rt->flags;
    rt_ipv4_addr_t nhipa = ipda;

    if (rt_flags & RT_LPM_F_LOCAL) {
        rt_pkt_ipv4_local_process(pkt);
        return;
    }

    if (rt_flags & RT_FWD_F_DISCARD) {
        if (pkt.pi != NULL) {
            rt_pkt_setup_dt(pkt.pi, ipda, rt, NULL);
        }
        rt_pkt_discard(pkt);
        return;
    }

    if (flags & PKT_SEND_F_UPDATE_IPSA) {
        rt_ipv4_hdr_t *ip = (rt_ipv4_hdr_t *) pkt.pp.l3;
        ip->ipsa = htonl(rt->pi->ipaddr);
        rt_pkt_ipv4_calc_chksum(ip);
    }

    if (rt_flags & RT_LPM_F_SUBNET) {
        nhipa = ipda;
    } else
    if (rt_flags & RT_LPM_F_HAS_NEXTHOP) {
        nhipa = rt->nhipa;
        assert(rt->pi != NULL);
    } else {
        dbgmsg(WARN, pkt, "Route Table Confusion (%u) %s",
            rdidx, rt_ipaddr_nr_str(ipda));
        rt_pkt_discard_error(pkt);
        return;
    }

    rt_ipv4_ar_t *ar = rt_ipv4_ar_lookup(rt->pi, nhipa);
    if ((ar == NULL) || (!(ar->flags & RT_AR_F_HAS_HWADDR))) {
        rt_arp_generate(pkt, nhipa, rt);
        return;
    }

    /* Create Direct-Table Entry */
    rt_pkt_setup_dt(pkt.pi, ipda, rt, ar);

    /* Update the MAC addresses */
    rt_pkt_set_hw_addrs(pkt, rt->pi, ar->hwaddr);

    rt_pkt_send(pkt, rt->pi);
}

static inline void
rt_pkt_ipv4_process (rt_pkt_t pkt, rt_ipv4_addr_t ipda)
{
    if ((ipda >> 28) == 0xf) {
        /* Multicast */
        rt_pkt_ipv4_local_process(pkt);
        return;
    }

    char t0[32], t1[32];
    rt_ipv4_addr_t ipsa = ntohl(*PTR(pkt.pp.l3, uint32_t, 12));
    dbgmsg(DEBUG, pkt, "IPv4 Slow Path (%u) %s -> %s", pkt.rdidx,
        rt_ipaddr_str(t0, ipsa),
        rt_ipaddr_str(t1, ipda));

    rt_pkt_ipv4_send(pkt, ipda, 0);
}

/*
 * Fast Dirct-Table Packet Processing
 */
static inline void
rt_pkt_dt_process (rt_pkt_t pkt, rt_dt_route_t *drp)
{
    if (unlikely(drp->flags)) {
        if (drp->flags & RT_FWD_F_DISCARD) {
            rt_pkt_discard(pkt);
            return;
        }
        if (drp->flags & RT_FWD_F_RANDDISC) {
            uint64_t rnd = (uint64_t) (uint32_t) rte_rand();
            if (rnd < g.rand_disc_level) {
                rt_pkt_discard(pkt);
                return;
            }
        }
    }
    /* Update MAC addresses */
    memcpy(&pkt.eth->dst, drp->eth.dst, 6);
    memcpy(&pkt.eth->src, drp->eth.src, 6);
    /* Send Packet */
    rt_pkt_send_fast(pkt, drp->port);
}

void
rt_pkt_process (int port, struct rte_mbuf *mbuf)
{
    rt_pkt_t pkt;
    pkt.pi = rt_port_lookup(port);
    pkt.rdidx = pkt.pi->rdidx;
    pkt.mbuf = mbuf;
    pkt.eth = rte_pktmbuf_mtod(mbuf, void *);

    uint16_t ethtype = ntohs(pkt.eth->ethtype);

    pkt.pp.l3 = PTR(pkt.eth, void, 14);
    rt_ipv4_addr_t ipda = ntohl(*PTR(pkt.pp.l3, uint32_t, 16));

    /* Look-up in Direct (fast) Table */
    if (likely(ethtype == 0x0800)) {
        rt_dt_key_t dt_key;
        dt_key.prtidx = port;
        dt_key.ipaddr = ipda;
        memcpy(dt_key.hwaddr, pkt.eth->dst, 6);
        rt_dt_route_t *drp = rt_dt_lookup(&dt_key);
        if (likely(drp != NULL)) {
            rt_pkt_dt_process(pkt, drp);
            return;
        }
    }

    if (likely(rt_pkt_is_unicast(pkt))) {
        /* Unicast - Compare Destination MAC address */
        if (rt_eth_addr_compare(&pkt.eth->dst, &pkt.pi->hwaddr)
                || (pkt.pi->flags & RT_PORT_F_PROMISC)) {
            /* Check for IPv4 */
            if (likely(ethtype == 0x0800)) {
                rt_pkt_ipv4_process(pkt, ipda);
                return;
            } else
            if (ethtype == 0x0806) {
                rt_arp_process(pkt);
                return;
            }
            dbgmsg(DEBUG, pkt, "unsupported ETHTYPE (0x%04x)",
                ethtype);
        } else {
            char ts[32];
            dbgmsg(DEBUG, pkt, "wrong destination MAC %s",
                rt_hwaddr_str(ts, pkt.eth->dst));
        }
    } else {
        /* Broadcast or Multicast */
        if (ethtype == 0x0800) {
            rt_pkt_ipv4_process(pkt, ipda);
            return;
        } else
        if (ethtype == 0x0806) {
            rt_arp_process(pkt);
            return;
        }
        dbgmsg(DEBUG, pkt, "unsupported ETHTYPE (0x%04x)",
            ethtype);
    }

    rt_pkt_discard_error(pkt);
}
