#include <string.h>

#include "defines.h"
#include "tables.h"
#include "pktutils.h"
#include "port.h"
#include "dbgmsg.h"
#include "functions.h"

typedef struct {
    uint16_t    hw_type;
    uint16_t    protocol;
    uint8_t     hw_addr_length;
    uint8_t     proto_addr_length;
    uint16_t    opcode;
    /* Sender Info */
    rt_eth_addr_t   s_hw_addr;
    rt_ipv4_addr_t  s_ip_addr;
    /* Target Info */
    rt_eth_addr_t   t_hw_addr;
    rt_ipv4_addr_t  t_ip_addr;
} __attribute__((packed)) rt_pkt_arp_t;

static void
rt_arp_pkt_ntoh (void *pkt, rt_pkt_arp_t *app)
{
    rt_pkt_arp_t ap;
    memcpy(&ap, pkt, sizeof(ap));
    memcpy(app, pkt, sizeof(ap));
    app->hw_type    = ntohs(ap.hw_type);
    app->protocol   = ntohs(ap.protocol);
    app->opcode     = ntohs(ap.opcode);
    app->s_ip_addr  = ntohl(ap.s_ip_addr);
    app->t_ip_addr  = ntohl(ap.t_ip_addr);
}

static void
rt_arp_pkt_hton (rt_pkt_arp_t *app, void *pkt)
{
    rt_pkt_arp_t ap;
    memcpy(&ap, app, sizeof(ap));
    ap.hw_type    = ntohs(ap.hw_type);
    ap.protocol   = ntohs(ap.protocol);
    ap.opcode     = ntohs(ap.opcode);
    ap.s_ip_addr  = ntohl(ap.s_ip_addr);
    ap.t_ip_addr  = ntohl(ap.t_ip_addr);
    memcpy(pkt, &ap, sizeof(ap));
}

static inline void
rt_ar_flush_packet (rt_ipv4_ar_t *ar)
{
    rt_pkt_t pkt;
    int rc = rt_ipv4_ar_get_pkt(&pkt, ar);
    if (rc == 1) {
        /* Update the MAC addresses */
        rt_pkt_set_hw_addrs(pkt, ar->pi, ar->hwaddr);
        dbgmsg(INFO, pkt, "Flush packet from AR entry");
        rt_pkt_send(pkt, ar->pi);
    }
}

static void
rt_arp_learn (rt_pkt_t pkt, rt_port_info_t *pi, rt_ipv4_addr_t ipaddr,
    rt_eth_addr_t hwaddr)
{
    if (ipaddr == 0) {
        dbgmsg(WARN, pkt, "ignore learning zero IPv4 address");
        return;
    }
    rt_lpm_t *rt = rt_lpm_lookup(pkt.rdidx, ipaddr);
    if (rt == NULL) {
        dbgmsg(DEBUG, pkt, "no route for received ARP (%s)",
            rt_ipaddr_nr_str(ipaddr));
        return;
    }
    if (rt->prefix.len == 32) {
        if (rt->flags & RT_FWD_F_LOCAL) {
            dbgmsg(WARN, pkt, "ARP with conflicting IP address (%u) %s",
                pkt.rdidx, rt_ipaddr_nr_str(ipaddr));
            return;
        }
        if ((rt->flags & RT_LPM_F_HAS_PORTINFO) && (rt->pi != pi)) {
            dbgmsg(WARN, pkt, "ARP with address (%u) %s of differnt"
                " port (%u)",
                pkt.rdidx, rt_ipaddr_nr_str(ipaddr), rt->pi->idx);
            return;
        }
    } 

    rt_ipv4_ar_t *ar = rt_ipv4_ar_learn(pi, ipaddr, hwaddr);
    rt_ar_flush_packet(ar);

    char ts[32];
    dbgmsg(CONF, nopkt, "ARP learned (%u) %s : %s",
       pkt.rdidx, rt_ipaddr_nr_str(ipaddr),
       rt_hwaddr_str(ts, hwaddr));
}

static inline void
rt_arp_request_process (rt_pkt_t pkt, rt_pkt_arp_t ap)
{
    rt_port_info_t *pi = pkt.pi;
    /* Check Target IP Address */
    rt_eth_addr_t *hwap = rt_lat_get_eth_addr(pi, ap.t_ip_addr);
    if (hwap == NULL) {
        char t0[32], t1[32];
        dbgmsg(DEBUG, pkt, "ARP request not for this port"
            " (req: %s, port(%d): %s)",
            rt_ipaddr_str(t0, ap.t_ip_addr), pi->idx,
            rt_ipaddr_str(t1, pi->ipaddr));
        rt_pkt_discard(pkt, RT_DISC_IGNORE);
        return;
    }
    /* Learn about the sender */
    rt_arp_learn(pkt, pi, ap.s_ip_addr, ap.s_hw_addr);
    /* Compose ARP Reply */
    rt_pkt_arp_t reply;
    memcpy(&reply, &ap, sizeof(ap));
    reply.opcode = 2;
    memcpy(reply.t_hw_addr, ap.s_hw_addr, 6);
    memcpy(&reply.t_ip_addr, &ap.s_ip_addr, 4);
    /* Use MAC address from Local Address Table */
    memcpy(reply.s_hw_addr, *hwap, 6);
    memcpy(&reply.s_ip_addr, &ap.t_ip_addr, 4);
    rt_arp_pkt_hton(&reply, pkt.pp.l3);
    /* Set Ethernet MAC addresses */
    rt_pkt_set_hw_addrs(pkt, pi, &ap.s_hw_addr);
    /* Debug Message */
    char t0[32], t1[32];
    dbgmsg(INFO, pkt, "ARP sending reply for (%u) %s back to %s", pkt.rdidx,
        rt_ipaddr_str(t0, reply.s_ip_addr),
        rt_ipaddr_str(t1, reply.t_ip_addr));
    /* Reply */
    rt_pkt_send(pkt, pi);
}

static inline void
rt_arp_reply_process (rt_pkt_t pkt, rt_pkt_arp_t ap)
{
    rt_rd_t rdidx = pkt.rdidx;
    rt_pkt_discard(pkt, RT_DISC_TERM);
    const char *optstr = "";

    rt_lpm_t *rt = rt_lpm_lookup_subnet(rdidx, ap.s_ip_addr);
    if (rt == NULL) {
        optstr = " - not on a subnet!";
    }

    char t0[32], t1[32], t2[32];
    dbgmsg(INFO, pkt, "ARP reply received from %s (%s) (local: (%u) %s)%s",
        rt_ipaddr_str(t0, ap.s_ip_addr),
        rt_hwaddr_str(t1, ap.s_hw_addr), rdidx,
        rt_ipaddr_str(t2, ap.t_ip_addr),
        optstr);

    if (rt == NULL)
        return;

    rt_ipv4_ar_t *ar = rt_ipv4_ar_learn(pkt.pi, ap.s_ip_addr, ap.s_hw_addr);
    rt_ar_flush_packet(ar);
}

void
rt_arp_process (rt_pkt_t pkt)
{
    rt_pkt_arp_t ap;
    rt_arp_pkt_ntoh(pkt.pp.l3, &ap);
    rt_disc_cause_t reason = RT_DISC_ERROR;

    if (ap.hw_type != 1) {
        dbgmsg(WARN, pkt, "ARP with bad HW type (0x%04x)",
            ap.hw_type);
        goto Discard;
    }
    if (ap.protocol != 0x0800) {
        dbgmsg(WARN, pkt, "ARP with bad protocol type (0x%04x)",
            ap.protocol);
        goto Discard;
    }
    if (ap.hw_addr_length != 6) {
        dbgmsg(WARN, pkt, "ARP with bad HW length (%u)",
            ap.hw_addr_length);
        goto Discard;
    }
    if (ap.proto_addr_length != 4) {
        dbgmsg(WARN, pkt, "ARP with bad protocol length (%u)",
            ap.proto_addr_length);
        goto Discard;
    }

    switch (ap.opcode) {
    case 1:
        rt_arp_request_process(pkt, ap);
        return;
    case 2:
        rt_arp_reply_process(pkt, ap);
        return;
    default:
        dbgmsg(WARN, pkt, "ARP with unsupported opcode (%u)", ap.opcode);
        goto Discard;
    }

  Discard:
    rt_pkt_discard(pkt, reason);
}

static inline void
rt_arp_send_request (rt_pkt_t pkt, rt_port_info_t *pi,
    rt_ipv4_addr_t ipda, void *buf)
{
    rt_pkt_arp_t ap;
    ap.hw_type      = 1;
    ap.protocol     = 0x0800;
    ap.hw_addr_length = 6;
    ap.proto_addr_length = 4;
    ap.opcode       = 1;
    /* Sender Info */
    memcpy(&ap.s_hw_addr, &pi->hwaddr, 6);
    /* Locate local IP address from route table */
    rt_lpm_t *srt = rt_lpm_lookup_subnet(pi->rdidx, ipda);
    if (srt == NULL) {
        char ts0[32];
        dbgmsg(WARN, nopkt, "ARP failed - (%u) %s is not in any subnet",
            pkt.rdidx, rt_ipaddr_str(ts0, ipda));
        rt_pkt_discard(pkt, RT_DISC_ERROR);
        return;
    }
    ap.s_ip_addr = srt->ifipa;
    /* Target Info */
    memset(&ap.t_hw_addr, 0, sizeof(ap.t_hw_addr));
    ap.t_ip_addr = ipda;
    rt_arp_pkt_hton(&ap, buf);

    dbgmsg(INFO, pkt, "ARP generated for (%u) %s on port %u",
        pkt.rdidx, rt_ipaddr_nr_str(ipda), pi->idx);

    rt_pkt_set_length(pkt, 14 + sizeof(rt_pkt_arp_t));
    rt_pkt_send(pkt, pi);
}

static inline void
rt_arp_request (rt_port_info_t *pi, rt_ipv4_addr_t ipda)
{
    /* Create new packet for ARP request */
    rt_pkt_t pkt;
    rt_pkt_create(&pkt);
    pkt.pi = pi;
    pkt.rdidx = pi->rdidx;

    rt_pkt_set_hw_addrs(pkt, pi, rt_eth_bcast_hw_addr);
    /* Set ETHTYPE to ARP */
    pkt.eth->ethtype = htons(0x0806);
    pkt.pp.l3 = &((uint8_t *) pkt.eth)[14];

    rt_arp_send_request(pkt, pi, ipda, pkt.pp.l3);
}

void
rt_arp_send_gratuitous (rt_port_info_t *pi)
{
    /* Create new packet for ARP request */
    rt_pkt_t pkt;
    rt_pkt_create(&pkt);
    pkt.pi = pi;
    pkt.rdidx = pi->rdidx;

    rt_pkt_set_hw_addrs(pkt, pi, rt_eth_bcast_hw_addr);
    /* Set ETHTYPE to ARP */
    pkt.eth->ethtype = htons(0x0806);
    pkt.pp.l3 = &((uint8_t *) pkt.eth)[14];

    rt_arp_send_request(pkt, pi, pi->ipaddr, pkt.pp.l3);
}

void
rt_arp_generate (rt_pkt_t pkt, rt_ipv4_addr_t ipda, rt_lpm_t *rt)
{
    rt_port_info_t *pi = rt->pi;
    int rc;

    rt_ipv4_ar_t *ar = rt_ipv4_ar_find_or_create(pi, ipda);
    assert(ar != NULL);
    rc = rt_ipv4_ar_set_pkt(pkt, ar);
    if (rc != 1) {
        rt_pkt_discard(pkt, RT_DISC_DROP);
    }

    rt_arp_request(pi, ipda);
}
