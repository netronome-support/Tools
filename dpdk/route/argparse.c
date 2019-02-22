#include <strings.h>
#include <stdio.h>
#include <arpa/inet.h>

#include "defines.h"
#include "port.h"
#include "tables.h"
#include "functions.h"
#include "dbgmsg.h"

typedef struct {
    const char *name;
    enum { FLAG, INTEGER, STRING } type;
    uint8_t index;
    void *ptr;
} opt_syntax_t;

static const opt_syntax_t *
opt_syntax_find (const opt_syntax_t *osp, const char *keyword)
{
    int i;
    for (i = 0 ; osp[i].name != NULL ; i++) {
        if (strcasecmp(osp[i].name, keyword) == 0)
            return &osp[i];
    }
    return NULL;
}


static int
parse_options (char *optstr, uint64_t *flags, opt_syntax_t *osp)
{
    while (optstr != NULL) {
        char *nxtopt = NULL;
        char *comma = index(optstr, ',');
        if (comma != NULL) {
            nxtopt = &comma[1];
            *comma = 0;
        }
        char *eqsign = index(optstr, '=');
        char *valstr = NULL;
        if (eqsign != NULL) {
            valstr = &eqsign[1];
            eqsign = 0;
        }
        const opt_syntax_t *sp = opt_syntax_find(osp, optstr);
        if (sp == NULL) {
            fprintf(stderr, "ERROR: could not parse '%s' option\n", optstr);
            return -1;
        }
        if (flags != NULL)
            *flags |= (1 << sp->index);
        switch (sp->type) {
            case INTEGER:
                break;
            case STRING:
                *((char **) sp->ptr) = valstr;
                break;
            default:
                break;
        }
        optstr = nxtopt;
    }
    return 0;
}

int
parse_iface_addr (const char *arg)
{
    /* Format: <portid>:[<domain>#][<ipv4 addr>[/<prefix length>]] */
    int rc;
    char tmpstr[128], *argstr = tmpstr, *endptr;
    const char *errmsg;
    strncpy(argstr, arg, 127);
    int plen = 32;
    rt_ipv4_addr_t ipaddr = 0;
    /* Parse Port Number */
    char *colon = index(argstr, ':');
    if (colon == NULL) {
        errmsg = "could not find ':'";
        goto Error;
    }
    *colon = 0; /* replace the colon with '\0' */
    long int port = strtol(argstr, &endptr, 10);
    if (endptr != colon) {
        errmsg = "could not parse port number";
        goto Error;
    }
    argstr = &colon[1];
    /* Get a pointer to the port info structure */
    rt_port_info_t *pi = rt_port_lookup(port);
    /* Parse Routing Domain */
    char *numch = index(argstr, '#');
    if (numch != NULL) {
        *numch = 0;
        int rdidx = strtol(argstr, &endptr, 10);
        if ((endptr != numch) || (rdidx < 1)) {
            errmsg = "could not parse routing domain index";
            goto Error;
        }
        argstr = &numch[1];
        rt_port_set_routing_domain(port, rdidx);
    }
    /* Check for options (starting with a ',') */
    char *optstr = NULL;
    char *comma = index(argstr, ',');
    if (comma != NULL) {
        *comma = 0;
        optstr = &comma[1];
    }
    if (strlen(argstr) == 0)
        return 0;
    /* Parse Prefix Length */
    char *slash = index(argstr, '/');
    if (slash != NULL) {
        *slash = 0;
        plen = strtol(&slash[1], &endptr, 10);
    }
    /* Parse IPv4 Address */
    rc = inet_pton(AF_INET, argstr, &ipaddr);
    if (rc != 1) {
        errmsg = "could not parse interface IP address ";
        goto Error;
    }
    ipaddr = ntohl(ipaddr);
    if (ipaddr != 0) {
        rt_port_set_ipv4_addr(port, ipaddr, plen);
    }
    if (optstr != NULL) {
        opt_syntax_t opts[] = {
            { "GRATARP", FLAG, 1, NULL },
            { NULL, 0, 0, NULL },
        };
        uint64_t flags = 0;
        int rc = parse_options(optstr, &flags, opts);
        if (rc < 0)
            return -1;
        if (flags & (1 << 1)) { /* GRATARP */
            pi->flags |= RT_PORT_F_GRATARP;
        }
    }
    return 0;

  Error:
    fprintf(stderr, "ERROR: %s '%s'.\n", errmsg, arg);
    return -1;
}

int
parse_ipv4_route (const char *arg)
{
    /* Format: [<rdidx>#]<IPv4 addr>/<prefix length>@[<rdidx>#]<next hop IPv4 addr> */
    int rc;
    char argstr[128];
    strncpy(argstr, arg, 127);
    int rdidx = RT_RD_DEFAULT;
    int nh_rdidx;
    int plen = 32;
    uint32_t nh_flags = 0;
    char *at = index(argstr, '@');
    if (at == NULL) {
        fprintf(stderr, "ERROR: could not parse route '%s'.\n",
            arg);
        return -1;
    }
    *at = 0;
    /* Parse route prefix (before @) */
    char *slash = index(argstr, '/');
    char *numch = index(argstr, '#');
    const char *sp_ipaddr = argstr;
    if (numch != NULL) {
        *numch = 0;
        rdidx = strtol(argstr, NULL, 10);
        sp_ipaddr = &numch[1];
    }
    if (slash != NULL) {
        plen = strtol(&slash[1], NULL, 10);
        *slash = 0;
    }
    rt_ipv4_addr_t ipaddr, nhipa;
    rc = inet_pton(AF_INET, sp_ipaddr, &ipaddr);
    if (rc != 1) {
        fprintf(stderr, "ERROR: could not parse route"
            " IP address '%s'.\n", arg);
        return -1;
    }
    /* Parse next-hop (after @) */
    const char *sp_nexthop = &at[1];
    const char *sp_numch = index(sp_nexthop, '#');
    if (sp_numch != NULL) {
        nh_rdidx = strtol(sp_nexthop, NULL, 10);
        printf("PARSE %d\n", nh_rdidx);
        sp_nexthop = &sp_numch[1];
    } else {
        nh_rdidx = rdidx;
    }
    if ((strcasecmp(sp_nexthop, "drop") == 0) ||
        (strcasecmp(sp_nexthop, "discard") == 0) ||
        (strcasecmp(sp_nexthop, "blackhole") == 0)) {
        nhipa = 0; /* Blackhole */
        nh_flags |= RT_LPM_F_DISCARD;
    } else {
        rc = inet_pton(AF_INET, sp_nexthop, &nhipa);
        if (rc != 1) {
            fprintf(stderr, "ERROR: could not parse next-hop"
                " IP address '%s'.\n", arg);
            return -1;
        }
        nh_flags |= RT_LPM_F_HAS_NEXTHOP;
    }

    rt_lpm_route_create(rdidx, ntohl(ipaddr), plen,
        nh_flags, ntohl(nhipa), nh_rdidx);

    char t0[32], t1[32];
    dbgmsg(CONF, nopkt, "Route (%u) %s/%u -> (%u) %s",
        rdidx, rt_ipaddr_str(t0, ntohl(ipaddr)), plen,
        nh_rdidx, rt_ipaddr_str(t1, ntohl(nhipa)));

    return 0;
}

int
parse_add_iface_addr (const char *arg)
{
    /* Format: <portid>:<ipv4 addr> */
    int rc;
    char tmpstr[128], *argstr = tmpstr, *endptr;
    const char *errmsg;
    strncpy(argstr, arg, 127);
    rt_ipv4_addr_t ipaddr = 0;
    int plen = 32;
    /* Parse Port Number */
    char *colon = index(argstr, ':');
    if (colon == NULL) {
        errmsg = "could not find ':'";
        goto Error;
    }
    *colon = 0; /* replace the colon with '\0' */
    /* Parse Port Index */
    long int port = strtol(argstr, &endptr, 10);
    if (endptr != colon) {
        errmsg = "could not parse port number";
        goto Error;
    }
    argstr = &colon[1];
    /* Parse Prefix Length */
    char *slash = index(argstr, '/');
    if (slash != NULL) {
        *slash = 0;
        plen = strtol(&slash[1], &endptr, 10);
    }
    /* Parse IPv4 Address */
    rc = inet_pton(AF_INET, argstr, &ipaddr);
    if (rc != 1) {
        errmsg = "could not parse interface IP address ";
        goto Error;
    }
    ipaddr = ntohl(ipaddr);
    /* Get a pointer to the port info structure */
    rt_port_info_t *pi = rt_port_lookup(port);
    /* Add interface address to LPM and Local Address Table */
    rt_lpm_add_iface_addr(pi, ipaddr, plen);
    return 0;

  Error:
    fprintf(stderr, "ERROR: %s '%s'.\n", errmsg, arg);
    return -1;
}

int
port_set_promisc_flag (const char *argstr)
{
    int prtidx = strtol(argstr, NULL, 10);
    if (prtidx >= RT_PORT_MAX) {
        fprintf(stderr, "ERROR: port index (%d) out of range\n",
            prtidx);
        return -1;
    }
    rt_port_info_t *pi = rt_port_lookup(prtidx);
    pi->flags |= RT_PORT_F_PROMISC;
    return 0;
}

static int
parse_hwaddr (const char *str, uint8_t *hwaddr)
{
    memset(hwaddr, 0, 6);
    int ch;
    int dc = 0; // Digit Count
    int bi = 0; // Byte Index
    while ((ch = *str++)) {
        if (ch == ':') {
            if (dc == 0)
                return -1;
            dc = 0;
            bi++;
            if (bi == 6)
                return -1;
        } else
        if (isdigit(ch)) {
            if (dc == 2)
                return -1;
            int value = (isdigit(ch))
                ? (ch - '0')
                : (tolower(ch) - 'a' + 10);
            hwaddr[bi] = 16 * hwaddr[bi] + value;
            dc++;
        } else {
            return -1;
        }
    }
    if ((bi != 5) || (dc == 0))
        return -1;
    return 0;
}

int
add_static_arp_entry (const char *argstr)
{
    /* Format: [<rdidx>#]<IPv4 addr>@<next hop MAC addr> */
    char tmpstr[128], ts0[32];
    int rc;
    strncpy(tmpstr, argstr, 127);
    argstr = tmpstr;
    int rdidx = RT_RD_DEFAULT;
    char *at    = index(tmpstr, '@');
    char *numch = index(tmpstr, '#');
    if (at == NULL) {
        fprintf(stderr, "missing '@' delimiter");
        return -1;
    }
    if (numch != NULL) {
        *numch = 0;
        char *endptr;
        rdidx = strtol(argstr, &endptr, 10);
        if ((endptr != numch) || (rdidx == 0)) {
            fprintf(stderr, "ERROR: could not parse routing domain index\n");
            return -1;
        }
        argstr = &numch[1];
    }
    *at = 0;
    rt_ipv4_addr_t nhipa;
    rc = inet_pton(AF_INET, argstr, &nhipa);
    if (rc != 1) {
        fprintf(stderr, "ERROR: could not parse route"
            " IP address '%s'\n", argstr);
        return -1;
    }
    nhipa = ntohl(nhipa);
    argstr = &at[1];
    rt_eth_addr_t hwaddr;
    rc = parse_hwaddr(argstr, hwaddr);
    if (rc) {
        fprintf(stderr, "ERROR: could not parse MAC address '%s'\n",
            argstr);
        return -1;
    }
    rt_lpm_t *rt = rt_lpm_add_nexthop(rdidx, nhipa);
    if (rt == NULL) {
        fprintf(stderr, "ERROR: no route for (%u) %s\n",
            rdidx, rt_ipaddr_nr_str(nhipa));
        return -1;
    }
    memcpy(rt->hwaddr, hwaddr, 6);
    rt->flags |= RT_LPM_F_HAS_HWADDR;
    dbgmsg(CONF, nopkt, "Static ARP Entry (%u) %s -> %s", rdidx,
        rt_ipaddr_nr_str(nhipa), rt_hwaddr_str(ts0, hwaddr));
    return 0;
}

int
parse_port_pinning (const char *arg)
{
    // Format: --pin 1:1,2 --pin <port>:<rx lcore>,<tx lcore>
    char argstr[128];
    strncpy(argstr, arg, 127);
    /* Character Position Pointers */
    char *cpp_colon = index(argstr, ':');
    char *cpp_comma = index(argstr, ',');
    int prtidx;
    rt_port_info_t *pi;
    char *endstr;
    if (cpp_colon == NULL)
        goto ParseError;
    *cpp_colon = 0;
    prtidx = strtol(argstr, &endstr, 10);
    if (*endstr != '\0')
        goto ParseError;
    pi = rt_port_lookup(prtidx);
    if (cpp_comma != NULL) {
        *cpp_comma = 0;
    }
    pi->rx_lcore = strtol(&cpp_colon[1], &endstr, 10);
    if (*endstr != '\0')
        goto ParseError;
    if (cpp_comma != NULL) {
        pi->tx_lcore = strtol(&cpp_comma[1], &endstr, 10);
        if (*endstr != '\0')
            goto ParseError;
    } else {
        pi->tx_lcore = pi->rx_lcore;
    }
    return 0;
  ParseError:
    fprintf(stderr, "ERROR: could not parse '%s'\n", arg);
    return -1;
}
