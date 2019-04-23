#include <strings.h>
#include <stdio.h>
#include <stdint.h>
#include <arpa/inet.h>
#include <getopt.h>
#include <values.h>

#include "defines.h"
#include "port.h"
#include "functions.h"
#include "dbgmsg.h"

#define ERR_MSG_MAX_LEN 1020
static char parse_err_msg[ERR_MSG_MAX_LEN + 2] = "";

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
parse_ll_integer (const char *arg, long long int *rvp,
    long long int min, long long int max)
{
    char *endptr = NULL;

    long long int n = strtol(arg, &endptr, 10);
    if (*endptr != '\0') {
        snprintf(parse_err_msg, ERR_MSG_MAX_LEN, "failed to parse %s", arg);
        return -1;
    }
    if ((n < min) || (n > max)) {
        snprintf(parse_err_msg, ERR_MSG_MAX_LEN, "value %s is out-of-range", arg);
        return -1;
    }
    if (rvp != NULL)
        *rvp = n;
    return 0;

    return n;
}

static int
parse_integer (const char *arg, int *rvp,
    int min, int max)
{
    char *endptr = NULL;

    /* parse number string */
    int n = (int) strtol(arg, &endptr, 10);
    if (*endptr != '\0') {
        snprintf(parse_err_msg, ERR_MSG_MAX_LEN, "failed to parse %s", arg);
        return -1;
    }
    if ((n < min) || (n > max)) {
        snprintf(parse_err_msg, ERR_MSG_MAX_LEN, "value %s is out-of-range", arg);
        return -1;
    }
    if (rvp != NULL)
        *rvp = n;
    return 0;

    return n;
}

static int
parse_double (const char *arg, double *rvp, double min, double max)
{
    char *endptr = NULL;
    double r = strtod(arg, &endptr);
    if (*endptr != '\0') {
        snprintf(parse_err_msg, ERR_MSG_MAX_LEN, "failed to parse %s", arg);
        return -1;
    }
    if ((r < min) || (r > max)) {
        snprintf(parse_err_msg, ERR_MSG_MAX_LEN, "value %s is out-of-range", arg);
        return -1;
    }
    if (rvp != NULL)
        *rvp = r;
    return 0;
}

static int
parse_fname (const char *fname, char **rvp)
{
    const char *lsp = rindex(fname, '/');
    if (lsp != NULL) {
        //const char *dname = strdup(fname);
        /* Check directory */
    }
    if (rvp != NULL) {
        *rvp = strdup(fname);
    }
    return 0;
}

static int
parse_ipv4_addr (const char *arg, ipv4_addr_t *rvp)
{
    ipv4_addr_t addr;
    int rc = inet_pton(AF_INET, arg, &addr);
    if (rc != 1) {
        snprintf(parse_err_msg, ERR_MSG_MAX_LEN, "invalid IPv4 address (%s)", arg);
        return -1;
    }
    if (rvp != NULL) {
        *rvp = ntohl(addr);
    }
    return 0;
}

static void
usage (const char *prgname)
{
    printf("\n%s [<EAL options>] -- [<application options>]\n\n", prgname);
    printf("Application Options:\n"
"  -h --help                - print this help\n"
"  --log-packets            - log packets in log file\n"
"  --log-pkt-len <int>      - Maximum packet size to capture in log\n"
"  --log-file <fname>       - Log File Name\n"
"  --port <index>           - Port Index\n"
"  --l-ip-addr <IPv4 addr>  - Local IP address\n"
"  --r-ip-addr <IPv4 addr>  - Local IP address\n"
"  --pkt-size <size>        - Ethernet packet size\n"
"  --static-ipv4-ar <>      - Static AR entry\n"
"  --dump-file <fname>      - Dump all samples to this file\n"
"  --count <ping count>     - maximum number of PINGs\n"
"  --duration <seconds>     - maximum duration of test\n"
"  --rate <pps>             - Ping rate\n"
    "\n");
}

/* Parse the argument given in the command line of the application */
int
parse_args (int argc, char **argv)
{
    int opt;
    int int_value;
    char **argvopt;
    int option_index;
    char *prgname = argv[0];
    static struct option lgopts[] = {
        { "help", no_argument, NULL, 'h'},
        { "port", required_argument, NULL, 'p'},
        { "count", required_argument, NULL, 'c'},
        { "duration", required_argument, NULL, 'T'},
        { "pkt-size", required_argument, NULL, 's'},
        { "l-ip-addr", required_argument, NULL, 1001},
        { "r-ip-addr", required_argument, NULL, 1002},
        { "static-ipv4-ar", required_argument, NULL, 1003},
        { "dump-file", required_argument, NULL, 1004},
        { "log-file", required_argument, NULL, 1005},
        { "log-level", required_argument, NULL, 1006},
        { "rate", required_argument, NULL, 'r'},
        { NULL, 0, 0, 0}
    };

    argvopt = argv;

    while ((opt = getopt_long(argc, argvopt, "hp:r:c:T:s:",
            lgopts, &option_index)) != EOF) {

        int rc = 0;
        const char *errmsg = NULL;
        switch (opt) {
        case 'h':
            usage(prgname);
            return -1;

        case 'p': /* --port */
            rc = parse_integer(optarg, &int_value, 0, MAXINT);
            if (rc) goto ParseError;
            g.prtidx = int_value;
            break;
        case 'r': /* --rate */
            rc = parse_double(optarg, &g.rate, 0.0, 100e6);
            if (rc) goto ParseError;
            break;
        case 'c': /* --count */
            rc = parse_ll_integer(optarg, (long long int *) &g.count, 0, MAXINT);
            if (rc) goto ParseError;
            break;
        case 'T': /* --duration */
            rc = parse_double(optarg, &g.duration, 0.0, 24.0 * 3600.0);
            if (rc) goto ParseError;
            break;
        case 's': /* --pkt-size */
            rc = parse_integer(optarg, &g.pktsize, 14 + 20 + 8 + 8, 9200);
            if (rc) goto ParseError;
            break;

        case 1001: /* --l-ip-addr */
            rc = parse_ipv4_addr(optarg, &g.l_ipv4_addr);
            if (rc) goto ParseError;
            break;
        case 1002: /* --r-ip-addr */
            rc = parse_ipv4_addr(optarg, &g.r_ipv4_addr);
            if (rc) goto ParseError;
            break;

        case 1003: /* --static-ipv4-ar */
            parse_hwaddr (optarg, g.r_hwaddr);
            g.have_hwaddr = 1;
            break;

        case 1004: /* --dump-file */
            rc = parse_fname(optarg, &g.dump_fname);
            if (rc) goto ParseError;
            break;

        case 1005: /* --log-file */
            rc = dbgmsg_fopen(optarg);
            if (rc) goto ParseError;
            break;
        case 1006: /* --log-level */
            rc = parse_integer(optarg, &dbgmsg_globals.log_level, 0, 5);
            if (rc) goto ParseError;
            break;

        /* long options */
        case 0:
            break;

        default:
            fprintf(stderr, "ERROR: failed parsing option (%d,%c)",
                opt, opt);
            return -1;
        ParseError:
            fprintf(stderr, "ERROR: failed parsing option (%s)",
                parse_err_msg);
            return -1;
            
        }
        if ((rc < 0) || (errmsg != NULL)) {
            if (errmsg != NULL)
                fprintf(stderr, "ERROR: %s\n", errmsg);
            return -1;
        }
    }

    if (optind >= 0)
        argv[optind-1] = prgname;

    optind = 0; /* reset getopt lib */
    return 0;
}
