#include <strings.h>
#include <stdio.h>
#include <stdint.h>
#include <arpa/inet.h>
#include <getopt.h>

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

static int
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

static int
parse_ipv4_route (const char *arg)
{
    /* Format: [<rdidx>#]<IPv4 addr>/<prefix length>@[<rdidx>#]<next hop IPv4 addr>[!<option>] */
    int rc;
    char argstr[128];
    strncpy(argstr, arg, 127);
    int rdidx = RT_RD_DEFAULT;
    int nh_rdidx;
    int plen = 32;
    uint32_t rt_flags = 0;
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
    char *sp_nexthop = &at[1];
    char *cp_exclam;
    while ((cp_exclam = rindex(sp_nexthop, '!')) != NULL) {
        const char *sp_option = &cp_exclam[1];
        *cp_exclam = 0;
        if (strcasecmp(sp_option, "randdisc") == 0) {
            rt_flags |= RT_FWD_F_RANDDISC;
            continue;
        }
    }
    char *sp_numch = index(sp_nexthop, '#');
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
        rt_flags |= RT_FWD_F_DISCARD;
    } else {
        rc = inet_pton(AF_INET, sp_nexthop, &nhipa);
        if (rc != 1) {
            fprintf(stderr, "ERROR: could not parse next-hop"
                " IP address '%s'.\n", arg);
            return -1;
        }
        rt_flags |= RT_LPM_F_HAS_NEXTHOP;
    }

    rt_lpm_t *rt = rt_lpm_route_create(rdidx, ntohl(ipaddr), plen,
        rt_flags, ntohl(nhipa), nh_rdidx);

    if (rt == NULL)
        return -1;

    char t0[32], t1[32];
    dbgmsg(CONF, nopkt, "Route (%u) %s/%u -> (%u) %s",
        rdidx, rt_ipaddr_str(t0, ntohl(ipaddr)), plen,
        nh_rdidx, rt_ipaddr_str(t1, ntohl(nhipa)));

    return 0;
}

static int
parse_add_iface_addr (const char *arg)
{
    /* Format: <portid>:<ipv4 addr>[/<prefix length>] */
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

static int
port_set_promisc_flag (const char *argstr)
{
    int prtidx = strtol(argstr, NULL, 10);
    if (prtidx >= RT_MAX_PORT_COUNT) {
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

static int
add_static_arp_entry (const char *argstr)
{
    /* Format: [<rdidx>#]<IPv4 addr>@<next hop MAC addr> */
    char tmpstr[128], ts0[32];
    int rc;
    strncpy(tmpstr, argstr, 127);
    argstr = tmpstr;
    int prtidx;
    char *at    = index(tmpstr, '@');
    char *colon = index(tmpstr, ':');
    if (at == NULL) {
        fprintf(stderr, "missing '@' delimiter");
        return -1;
    }
    if (colon == NULL) {
        goto ParseError;
    }
    *colon = 0;
    char *endptr;
    prtidx = strtol(argstr, &endptr, 10);
    if (endptr != colon) {
        fprintf(stderr, "ERROR: could not parse port index\n");
        return -1;
    }
    argstr = &colon[1];
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

    rt_port_info_t *pi = rt_port_lookup(prtidx);
    rt_ipv4_ar_learn(pi, nhipa, hwaddr);

    dbgmsg(CONF, nopkt, "Static ARP Entry (%u) %s -> %s", prtidx,
        rt_ipaddr_nr_str(nhipa), rt_hwaddr_str(ts0, hwaddr));

    return 0;
  ParseError:
    fprintf(stderr, "ERROR: could not parse '%s'\n", argstr);
    return -1;
}

static int
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

/* display usage */
static void
usage (const char *prgname)
{
    printf("\n%s [<EAL options>] -- [<application options>]\n\n", prgname);
    printf("Application Options:\n"
"  -h --help                - print this help\n"
"  --log-packets            - log packets in log file\n"
"  --log-pkt-len <int>      - Maximum packet size to capture in log\n"
"  --no-statistics          - do not print statistics\n"
"  --ping-nexthops          - ping all route-nexthops\n"
"  -p --port-bitmap <port bitmap>\n"
"                           - hexadecimal bitmask of ports\n"
"  -q <queue count>         - number of queue (=ports) per lcore (default is 1)\n"
"  --iface-addr <portid>:[<domain>#][<ipv4 addr>[/<prefix length>]]\n"
"                           - specify interface parameters\n"
"  --static [<rdidx>#]<IPv4 addr>@<next hop MAC addr>\n"
"                           - add static address resolution entry\n"
"  --add-iface-addr <portid>:<ipv4 addr>[/<prefix length>]\n"
"                           - add sub-interface to port\n"
"  --route [<rdidx>#]<IPv4 addr>/<prefix length>@[<rdidx>#]<next hop IPv4 addr>[!<option>]\n"
"                           - add route\n"
"  --log-file <file name>   - specify log-file\n"
"  --pin <port>:<rx lcore>[,<tx lcore>]\n"
"                           - static lcore-port pinning\n"
"  --rand-disc-level <val>  - discard rate (percent) for RANDDISC routes\n"
    "\n");
}

static uint64_t
rt_parse_portmask (const char *portmask)
{
    char *end = NULL;
    uint64_t pm;

    /* parse hexadecimal string */
    pm = strtoull(portmask, &end, 16);
    if ((portmask[0] == '\0') || (end == NULL) || (*end != '\0'))
        return -1;

    if (pm == 0)
        return -1;

    return pm;
}

static unsigned int
rt_parse_nqueue (const char *q_arg)
{
    char *end = NULL;
    unsigned long n;

    /* parse hexadecimal string */
    n = strtoul(q_arg, &end, 10);
    if ((q_arg[0] == '\0') || (end == NULL) || (*end != '\0'))
        return 0;
    if (n == 0)
        return 0;
    if (n >= MAX_RX_QUEUE_PER_LCORE)
        return 0;

    return n;
}

static int
rt_parse_timer_period (const char *q_arg)
{
    char *end = NULL;
    int n;

    /* parse number string */
    n = strtol(q_arg, &end, 10);
    if ((q_arg[0] == '\0') || (end == NULL) || (*end != '\0'))
        return -1;
    if (n >= MAX_TIMER_PERIOD)
        return -1;

    return n;
}

static int
rt_parse_random_discard_level (const char *arg)
{
    double percent = strtod(arg, NULL);
    if ((percent < 0.0) || (percent > 100.0))
        return -1;
    g.rand_disc_level = (uint64_t) (((double) INT_MAX) * percent / 100.0);
    return 0;
}

/* Parse the argument given in the command line of the application */
int
rt_parse_args (int argc, char **argv)
{
    int opt, ret, timer_secs;
    char **argvopt;
    int option_index;
    char *prgname = argv[0];
    static struct option lgopts[] = {
        { "help", no_argument, NULL, 'h'},
        { "port-bitmap", required_argument, NULL, 'p'},
        { "iface-addr", required_argument, NULL, 1001},
        { "route", required_argument, NULL, 1002},
        { "log-file", required_argument, NULL, 1003},
        { "promisc", required_argument, NULL, 1004},
        { "static", required_argument, NULL, 1005},
        { "log-level", required_argument, NULL, 1006},
        { "pin", required_argument, NULL, 1007},
        { "add-iface-addr", required_argument, NULL, 1008},
        { "rand-disc-level", required_argument, NULL, 1009},
        { "log-packets", no_argument, &dbgmsg_globals.log_packets, 1},
        { "log-pkt-len", required_argument, NULL, 1010},
        { "no-statistics", no_argument, &g.print_statistics, 0},
        { "ping-nexthops", no_argument, &g.ping_nexthops, 1},
        { NULL, 0, 0, 0}
    };

    argvopt = argv;

    while ((opt = getopt_long(argc, argvopt, "hp:q:T:",
            lgopts, &option_index)) != EOF) {

        int rc = 0;
        const char *errmsg = NULL;
        switch (opt) {
        case 'h':
            usage(prgname);
            return -1;
        /* portmask */
        case 'p':
            g.enabled_port_mask = rt_parse_portmask(optarg);
            if (g.enabled_port_mask == 0) {
                errmsg = "invalid portmask";
            }
            break;

        /* nqueue */
        case 'q':
            g.rx_queue_per_lcore = rt_parse_nqueue(optarg);
            if (g.rx_queue_per_lcore == 0) {
                errmsg = "invalid queue number";
            }
            break;

        /* timer period */
        case 'T':
            timer_secs = rt_parse_timer_period(optarg);
            if (timer_secs < 0) {
                errmsg = "ERROR: invalid timer period";
                break;
            }
            g.timer_period = timer_secs;
            break;

        case 1001:
            rc = parse_iface_addr(optarg);
            break;

        case 1002:
            rc = parse_ipv4_route(optarg);
            break;

        case 1003:
            rc = dbgmsg_fopen(optarg);
            break;

        case 1004:
            rc = port_set_promisc_flag(optarg);
            break;

        case 1005:
            rc = add_static_arp_entry(optarg);
            break;

        case 1006: /* --log-level */
            dbgmsg_globals.log_level = strtol(optarg, NULL, 10);
            break;

        case 1007: /* --pin */
            rc = parse_port_pinning(optarg);
            break;

        case 1008: /* --add-iface-addr */
            rc = parse_add_iface_addr(optarg);
            break;

        case 1009: /* --rand-disc-level */
            rc = rt_parse_random_discard_level(optarg);
            break;

         case 1010: /* --log-pkt-len */
            dbgmsg_globals.log_pkt_len = strtol(optarg, NULL, 10);
            break;

       /* long options */
        case 0:
            break;

        default:
            usage(prgname);
            errmsg = "could not parse command line";
            break;
        }
        if ((rc < 0) || (errmsg != NULL)) {
            if (errmsg != NULL)
                fprintf(stderr, "ERROR: %s\n", errmsg);
            return -1;
        }
    }

    if (optind >= 0)
        argv[optind-1] = prgname;

    ret = optind - 1;
    optind = 0; /* reset getopt lib */
    return ret;
}
