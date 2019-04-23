#include <string.h>

#include "defines.h"
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
    eth_addr_t   s_hw_addr;
    ipv4_addr_t  s_ip_addr;
    /* Target Info */
    eth_addr_t   t_hw_addr;
    ipv4_addr_t  t_ip_addr;
} __attribute__((packed)) pkt_arp_t;

static void
arp_pkt_ntoh (void *pkt, pkt_arp_t *app)
{
    pkt_arp_t ap;
    memcpy(&ap, pkt, sizeof(ap));
    memcpy(app, pkt, sizeof(ap));
    app->hw_type    = ntohs(ap.hw_type);
    app->protocol   = ntohs(ap.protocol);
    app->opcode     = ntohs(ap.opcode);
    app->s_ip_addr  = ntohl(ap.s_ip_addr);
    app->t_ip_addr  = ntohl(ap.t_ip_addr);
}

static void
arp_pkt_hton (pkt_arp_t *app, void *pkt)
{
    pkt_arp_t ap;
    memcpy(&ap, app, sizeof(ap));
    ap.hw_type    = ntohs(ap.hw_type);
    ap.protocol   = ntohs(ap.protocol);
    ap.opcode     = ntohs(ap.opcode);
    ap.s_ip_addr  = ntohl(ap.s_ip_addr);
    ap.t_ip_addr  = ntohl(ap.t_ip_addr);
    memcpy(pkt, &ap, sizeof(ap));
}

static inline void
arp_request_process (pkt_t pkt, pkt_arp_t ap)
{
    /* Compose ARP Reply */
    pkt_arp_t reply;
    memcpy(&reply, &ap, sizeof(ap));
    reply.opcode = 2;
    memcpy(reply.t_hw_addr, ap.s_hw_addr, 6);
    memcpy(&reply.t_ip_addr, &ap.s_ip_addr, 4);
    /* Use MAC address from Local Address Table */
    port_info_t *pi = port_lookup(g.prtidx);
    memcpy(reply.s_hw_addr, pi->hwaddr, 6);
    memcpy(&reply.s_ip_addr, &ap.t_ip_addr, 4);
    arp_pkt_hton(&reply, pkt.pp.l3);
    /* Set Ethernet MAC addresses */
    pkt_set_hw_addrs(pkt, &ap.s_hw_addr);
    /* Debug Message */
    char t0[32], t1[32];
    dbgmsg(INFO, pkt, "ARP sending reply for %s back to %s",
        ipaddr_str(t0, reply.s_ip_addr),
        ipaddr_str(t1, reply.t_ip_addr));
    /* Reply */
    pkt_send(pkt, g.prtidx);
}

static inline void
arp_reply_process (pkt_t pkt, pkt_arp_t ap)
{
    char t0[32], t1[32], t2[32];
    dbgmsg(INFO, pkt, "ARP reply received from %s (%s) (local: %s)",
        ipaddr_str(t0, ap.s_ip_addr),
        hwaddr_str(t1, ap.s_hw_addr),
        ipaddr_str(t2, ap.t_ip_addr));

    pkt_discard(pkt);

    if (ap.s_ip_addr != g.r_ipv4_addr)
        return;

    memcpy(g.r_hwaddr, ap.s_hw_addr, 6);
    g.have_hwaddr = 1;
}

void
arp_process (pkt_t pkt)
{
    pkt_arp_t ap;
    arp_pkt_ntoh(pkt.pp.l3, &ap);

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
        arp_request_process(pkt, ap);
        return;
    case 2:
        arp_reply_process(pkt, ap);
        return;
    default:
        dbgmsg(WARN, pkt, "ARP with unsupported opcode (%u)", ap.opcode);
        goto Discard;
    }

  Discard:
    pkt_discard(pkt);
}

static inline void
arp_send_request (pkt_t pkt, ipv4_addr_t ipda, void *buf)
{
    pkt_arp_t ap;
    ap.hw_type      = 1;
    ap.protocol     = 0x0800;
    ap.hw_addr_length = 6;
    ap.proto_addr_length = 4;
    ap.opcode       = 1;
    /* Sender Info */
    port_info_t *pi = port_lookup(g.prtidx);
    memcpy(&ap.s_hw_addr, pi->hwaddr, 6);
    ap.s_ip_addr = g.l_ipv4_addr;
    /* Target Info */
    memset(&ap.t_hw_addr, 0, sizeof(ap.t_hw_addr));
    ap.t_ip_addr = ipda;
    arp_pkt_hton(&ap, buf);

    char t0[32], t1[32];
    dbgmsg(INFO, pkt, "ARP request generated for %s (local: %s)",
        ipaddr_str(t0, ap.t_ip_addr),
        ipaddr_str(t1, ap.s_ip_addr));

    pkt_set_length(pkt, 14 + sizeof(pkt_arp_t));
    pkt_send(pkt, g.prtidx);
}

static inline void
arp_request (ipv4_addr_t ipda)
{
    /* Create new packet for ARP request */
    pkt_t pkt;
    pkt_create(&pkt);

    pkt_set_hw_addrs(pkt, eth_bcast_hw_addr);
    /* Set ETHTYPE to ARP */
    pkt.eth->ethtype = htons(0x0806);
    pkt.pp.l3 = &((uint8_t *) pkt.eth)[14];

    arp_send_request(pkt, ipda, pkt.pp.l3);
}

void
arp_generate (pkt_t pkt, ipv4_addr_t ipda)
{
    pkt_discard(pkt);
    arp_request(ipda);
}
