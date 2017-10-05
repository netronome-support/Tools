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
