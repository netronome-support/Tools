#include <stdlib.h>
#include <stdint.h>
#include <arpa/inet.h>

#include "defines.h"
#include "pktutils.h"
#include "dbgmsg.h"
#include "functions.h"

static int
rt_mask_to_plen (uint32_t mask)
{
    int i;
    uint32_t cmpmsk = 0xffffffff;
    for (i = 32 ; i > 0 ; i--) {
        if (mask == cmpmsk)
            return i;
        cmpmsk = cmpmsk << 1;
    }
    return 0;
}

typedef struct {
    uint8_t     opcode;
    uint8_t     hw_type; /* 1 */
    uint8_t     hw_length; /* 6 */
    uint8_t     hops;
    uint32_t    transaction;
    uint16_t    seconds;
    uint16_t    broadcast;
    uint32_t    client_ip_addr;
    uint32_t    your_ip_addr;
    uint32_t    server_ip_addr;
    uint32_t    gateway_ip_addr;
    uint8_t     client_hw_addr[16];
    uint8_t     server_name[64];
    uint8_t     file_name[128];
    uint32_t    cookie;
} __attribute__((packed)) rt_pkt_dhcp_t;

typedef struct {
    uint8_t msgtype;
    rt_ipv4_addr_t mask;
    uint8_t plen;
    rt_ipv4_addr_t dhcp_srv_ipaddr;
} rt_dhcp_options_t;

static void
rt_dhcp_options_parse (rt_pkt_dhcp_t *dhcp, rt_dhcp_options_t *opts)
{
    uint8_t *p = (uint8_t *) &dhcp[1];
    memset(opts, 0, sizeof(rt_dhcp_options_t));
    /* RFC 2132 */
    for (;;) {
        uint8_t code = p[0];
        uint8_t len  = p[1];
        if (code == 0) {
            p++;
            continue;
        }
        if (code == 0xff)
            return;
        switch (code) {
            case 1: /* Subnet mask */
                opts->mask = ntohl(*PTR(p, uint32_t, 2));
                opts->plen = rt_mask_to_plen(opts->mask);
                break;
            case 53: /* Message Type */
                opts->msgtype = p[2];
                break;
            case 54:
                opts->dhcp_srv_ipaddr = ntohl(*PTR(p, uint32_t, 2));
                break;
        }
        p += 2 +len;
    }
}

typedef struct {
    uint8_t *p;
    int len;
    /* Temporary Space for options data */
    union {
      uint8_t data[32];
      uint32_t ipaddr;
    };
} rt_dhcp_opts_state_t;

static void
rt_dhcp_opts_append (rt_dhcp_opts_state_t *os,
    uint8_t code, uint8_t len, void *data)
{
    os->p[0] = code;
    if ((code == 0) || (code == 0xff)) {
        os->len += 1;
        os->p   += 1;
        return;
    }
    os->p[1] = len;
    memcpy(&os->p[2], data, len);
    os->p   += 2 + len;
    os->len += 2 + len;
}

static void
rt_dhcp_transmit (rt_port_info_t *pi, rt_dhcp_info_t *info, uint8_t msgtype)
{
    rt_pkt_t pkt;
    rt_pkt_create(&pkt);
    pkt.pi = pi;
    pkt.rdidx = pi->rdidx;

    /* Prepare Ethernet, IP, and UDP headers */
    rt_pkt_set_hw_addrs(pkt, pi, rt_eth_bcast_hw_addr);
    rt_pkt_ipv4_setup(&pkt, 17, 0, 0xffffffff);
    rt_ipv4_hdr_t *ip = pkt.pp.l3;
    rt_udp_hdr_t *udp = PTR(ip, void, 20);
    rt_pkt_dhcp_t *dhcp = PTR(udp, void, 8);
    rt_pkt_udp_setup(udp, 0, 68, 67);

    /* Setup DHCP header */
    memset(dhcp, 0, sizeof(rt_pkt_dhcp_t));
    dhcp->opcode = 1;
    dhcp->hw_type = 1;
    dhcp->hw_length = 6;
    dhcp->broadcast = htons(0x8000);
    dhcp->transaction = htonl(info->transaction);
    memcpy(dhcp->client_hw_addr, pi->hwaddr, 6);
    dhcp->cookie = htonl(0x63825363);

    rt_dhcp_opts_state_t os;
    os.p = (uint8_t *) &dhcp[1];
    os.len = 0;

    /* Option 53: Message Type */
    rt_dhcp_opts_append(&os, 53, 1, &msgtype);

    switch (msgtype) {
        case 1: /* DHCP DISCOVER */
            os.data[0] = 1; /* Subnet Mask */
            rt_dhcp_opts_append(&os, 55, 1, os.data);
            break;
        case 3: /* DHCP REQUEST */
            dhcp->server_ip_addr = htonl(info->srv_ipaddr);
            /* option 50: Requested IPv4 address */
            os.ipaddr = htonl(info->offer_ipv4_addr);
            rt_dhcp_opts_append(&os, 50, 4, os.data);
            /* option 54: Server IPv4 address */
            os.ipaddr = htonl(info->srv_ipaddr);
            rt_dhcp_opts_append(&os, 54, 4, os.data);
            break;
    }

    /* Add End-of-Message Options */
    rt_dhcp_opts_append(&os, 0xff, 0, NULL);

    /* Update various length fields */
    int udp_total_len = 8 + sizeof(*dhcp) + os.len;
    int ip_total_len = 20 + udp_total_len;
    udp->length = htons(udp_total_len);
    ip->length = htons(ip_total_len);
    rt_pkt_set_length(pkt, 14 + ip_total_len);

    /* Calculate IPv4 and UDP checksums */
    rt_pkt_ipv4_calc_chksum(ip);
    rt_pkt_udp_calc_chksum(ip);

    rt_pkt_send(pkt, pi);
}

void
rt_dhcp_discover (void)
{
    int prtidx;
    for (prtidx = 0 ; prtidx < RT_PORT_MAX ; prtidx++) {
        rt_port_info_t *pi = rt_port_lookup(prtidx);
        if ((pi->rdidx != 0) && (pi->ipaddr == 0)) {
            rt_dhcp_info_t *info = &pi->dhcpinfo;
            info->transaction = lrand48();
            info->state = 1;
            rt_dhcp_transmit (pi, info, 1);
        }
    }
}

void
rt_dhcp_process (rt_pkt_t pkt)
{
    rt_port_info_t *pi = pkt.pi;
    rt_dhcp_info_t *info = &pi->dhcpinfo;
    rt_pkt_dhcp_t *dhcp = PTR(pkt.pp.l3, void, 28);
    rt_dhcp_options_t opts;

    if (dhcp->opcode != 2) {
        dbgmsg(WARN, pkt, "DCHP wrong opcode (%u)", dhcp->opcode);
        goto Discard;
    }
    if (info->transaction != ntohl(dhcp->transaction)) {
        dbgmsg(WARN, pkt, "DCHP wrong transaction ID");
        goto Discard;
    }

    rt_dhcp_options_parse(dhcp, &opts);
    rt_ipv4_addr_t l_ipaddr = ntohl(dhcp->your_ip_addr);
    switch (opts.msgtype) {
        case 2: /* DHCP OFFER */
            dbgmsg(INFO, pkt, "DHCP OFFER received (%s/%u)",
                rt_ipaddr_nr_str(l_ipaddr), opts.plen);
            info->offer_ipv4_addr = l_ipaddr;
            info->srv_ipaddr = opts.dhcp_srv_ipaddr;
            /* Send DHCP REQUEST */
            rt_dhcp_transmit(pi, info, 3);
            info->state = 3;
            break;
        case 5: /* DHCP ACK */
            info->state = 5;
            dbgmsg(CONF, pkt, "DHCP ACK received (%s/%u)",
                rt_ipaddr_nr_str(l_ipaddr), opts.plen);
            rt_port_set_ipv4_addr(pi->idx, l_ipaddr, opts.plen);
            break;
        case 6: /* DHCP NEG-ACK */
            dbgmsg(INFO, pkt, "DHCP NEG-ACK received");
            info->state = 0;
            break;
        default:
            dbgmsg(WARN, pkt, "DHCP unsupported message (%u)", opts.msgtype);
            break;
    }

  Discard:
    rt_pkt_discard(pkt);
}
