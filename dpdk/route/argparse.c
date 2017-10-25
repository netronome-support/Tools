#include <strings.h>
#include <stdio.h>
#include <arpa/inet.h>

#include "defines.h"
#include "port.h"
#include "tables.h"
#include "functions.h"
#include "dbgmsg.h"


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
    /* Parse Routing Domain */
    char *numch = index(argstr, '#');
    if (numch != NULL) {
        *numch = 0;
        int rdidx = strtol(argstr, &endptr, 10);
        if ((endptr != numch) || (rdidx == 0)) {
            errmsg = "could not parse routing domain index";
            goto Error;
        }
        argstr = &numch[1];
        rt_port_set_routing_domain(port, rdidx);
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
    return 0;

  Error:
    fprintf(stderr, "ERROR: %s '%s'.\n", errmsg, arg);
    return -1;
}

int
parse_ipv4_route (const char *arg)
{
    /* Format: [<rdidx>#]<IPv4 addr>/<prefix length>@<next hop IPv4 addr> */
    int rc;
    char argstr[128];
    strncpy(argstr, arg, 127);
    int rdidx = RT_RD_DEFAULT;
    int plen = 32;
    char *slash = index(argstr, '/');
    char *at    = index(argstr, '@');
    char *numch = index(argstr, '#');
    if (at == NULL) {
        fprintf(stderr, "ERROR: could not parse route '%s'.\n",
            arg);
        return -1;
    }
    *at = 0;
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
    if ((strcasecmp(&at[1], "drop") == 0) ||
        (strcasecmp(&at[1], "discard") == 0) ||
        (strcasecmp(&at[1], "blackhole") == 0)) {
        nhipa = 0; /* Blackhole */
    } else {
        rc = inet_pton(AF_INET, &at[1], &nhipa);
        if (rc != 1) {
            fprintf(stderr, "ERROR: could not parse next-hop"
                " IP address '%s'.\n", arg);
            return -1;
        }
    }

    rt_lpm_route_create(rdidx, ntohl(ipaddr), plen, ntohl(nhipa));

    char t0[32], t1[32];
    dbgmsg(INFO, nopkt, "Route (%u) %s/%u -> %s", rdidx,
        rt_ipaddr_str(t0, ntohl(ipaddr)), plen,
        rt_ipaddr_str(t1, ntohl(nhipa)));

    return 0;
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
    char tmpstr[128];
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
    dbgmsg(INFO, nopkt, "Static ARP Entry (%u) %s -> %s", rdidx,
        rt_ipaddr_nr_str(nhipa), rt_hwaddr_str(hwaddr));
    return 0;
}
