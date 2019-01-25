#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/time.h>
#include <ctype.h>
#include <unistd.h>

#define F_LIST_COUNT        (1 << 0)
#define F_LIST_REF          (1 << 1)
#define F_LIST_DROP         (1 << 2)
#define F_LIST_ONCE         (1 << 3)
#define F_LIST_NOHEADER     (1 << 4)
#define F_LIST_NORM         (1 << 5)
#define F_LIST_TOTAL        (1 << 6)
#define F_LIST_PKTSIZE      (1 << 7)
#define F_LIST_IGNZERO      (1 << 8)
#define F_LIST_IGNMISSING   (1 << 9)

#define SAMPLE_COUNT  16

typedef struct {
    uint64_t pkt;
    uint64_t oct;
    uint64_t err;
    uint64_t drop;
} cntset_t;

typedef struct {
    struct timeval tv0; /* Time-Stamp before acquisition */
    struct timeval tv1; /* Time-Stamp after acquisition */
    cntset_t r; /* Receive Counters */
    cntset_t t; /* Transmit Counters */
} sample_t;

typedef struct {
    enum { IFACE, TOTAL_RESET, TOTAL, SPACE } type;
    const char *ifname;
    sample_t smpl[SAMPLE_COUNT];
    sample_t ref; /* Start (reference) value */
} ifdata_t;

/*
 * Add 'sp' counter-set to 'tp'
 */
static inline void
cntset_aggregate (cntset_t *tp, const cntset_t *sp)
{
    tp->pkt  += sp->pkt;
    tp->oct  += sp->oct;
    tp->err  += sp->err;
    tp->drop += sp->drop;
}

/*
 * Add all counters of sample 'sp' to 'tp'
 */
static void
sample_aggregate (sample_t *tp, const sample_t *sp)
{
    cntset_aggregate(&tp->r, &sp->r);
    cntset_aggregate(&tp->t, &sp->t);
    tp->tv0 = sp->tv0;
    tp->tv1 = sp->tv1;
}

/*
 * Collect a sample of 'ifname' from /proc/net/dev
 *
 * This method is a bit wasteful since it re-parses the proc file
 * repeatedly, once for each interface. To be improved ...
 */
int
sample (const char *ifname, sample_t *sp)
{
    /* BUG!!!!!!!!!!
     * The drop counters in /proc/net/dev are only 32-bit !!!
     */
    char *str, buf[200];
    int rc = 0;
    int ifnlen = strlen(ifname);
    FILE *fd = fopen("/proc/net/dev", "r");
    if (fd == NULL)
        return -1;
    gettimeofday(&sp->tv0, NULL);
    while ((str = fgets(buf, 200, fd)) != NULL) {
        while (isspace(*str))
            str++;
        char *strt = index(str, ':');
        if (strt == NULL)
            continue;
        if ((strt - str) != ifnlen)
            continue;
        if (strncmp(str, ifname, ifnlen) == 0) {
            int i;
            str = &strt[1];
            for (i = 0 ; (str != NULL) && (i < 16) ; i++) {
                unsigned long long int d;
                d = strtoull(str, &str, 0);
                switch (i) {
                    case  0: sp->r.oct  = d; break;
                    case  1: sp->r.pkt  = d; break;
                    case  2: sp->r.err  = d; break;
                    case  3: sp->r.drop = d; break;
                    case  8: sp->t.oct  = d; break;
                    case  9: sp->t.pkt  = d; break;
                    case 10: sp->t.err  = d; break;
                    case 11: sp->t.drop = d; break;
                }
            }
            rc = 1;
            break;
        }
    }
    gettimeofday(&sp->tv1, NULL);
    fclose(fd);
    return rc;
}

static int
ifaceZero (const cntset_t *cp0, const cntset_t *cp1)
{
    return ! (
        (cp0->pkt  != 0) ||
        (cp1->pkt  != 0) ||
        (cp0->drop != 0) ||
        (cp1->drop != 0) ||
        (cp0->err  != 0) ||
        (cp1->err  != 0));
}

/*
 * Print Counter-Set to string (either receive or transmit counters)
 */
static inline int
printCntSet (int mode, int flags, char *str,
    const cntset_t *cp0, /* Earlier counter-set used for rate-calc */
    const cntset_t *cp1, /* Most recent counter set */
    float f,             /* Time Interval factor */
    const cntset_t ref)  /* Reference counter set */
{
    /* Start by printing packet and bit rates */
    int n = sprintf(str, "%10.3f  %11.3f",
        f * ((float) (cp1->pkt - cp0->pkt)) / 1e3,
        f * (float) (cp1->oct - cp0->oct) * 8.0 / 1e6);
    /* Print normalized bit-rate (includes inter-packet gap) */
    if (flags & F_LIST_NORM) {
        long int oct = (cp1->oct - cp0->oct)
                + 20 * (cp1->pkt - cp0->pkt); // Should this be '24'?
        n += sprintf(&str[n], "  %6.2f",
            f * (float) oct * 8.0 / 10e6 / 100.0);
    }
    /* Print APS (average packet size) */
    if (flags & F_LIST_PKTSIZE) {
        int pktdiff = cp1->pkt - cp0->pkt;
        unsigned int aps = (pktdiff == 0) ? 0
            : ((cp1->oct - cp0->oct) / pktdiff);
        char buf[32] = "";
        if (pktdiff > 0)
            sprintf(buf, "%u", aps);
        else if (flags & F_LIST_ONCE)
            strcpy(buf, "-");
        n += sprintf(&str[n], "%8s", buf);
    }
    /* Print packet counter */
    if (flags & F_LIST_COUNT) {
        n += sprintf(&str[n], "  %12llu",
          (long long unsigned int) cp1->pkt - ((flags & F_LIST_REF)
            ? ref.pkt : 0));
    }
    /* Print drop counter */
    if (flags & F_LIST_DROP) {
        n += sprintf(&str[n], "  %12llu",
          (long long unsigned int)
          (cp1->drop - ((flags & F_LIST_REF) ? ref.drop : 0)));
    }
    return n;
}

static int
printHeader (char *str, int flags)
{
    int w = 23;
    int n = 0;
    char head[256] = "";
    strcat(head, "      Kpps");
    strcat(head, "         Mbps");
    if (flags & F_LIST_NORM) {
        // 100.0
        strcat(head, "      GE");
        w += 8;
    }
    if (flags & F_LIST_PKTSIZE) {
        strcat(head, "     APS");
        w += 8;
    }
    if (flags & F_LIST_COUNT) {
        strcat(head, "           cnt");
        w += 14;
    }
    if (flags & F_LIST_DROP) {
        strcat(head, "          drop");
        w += 14;
    }
    const char *fields = (flags & 1)
        ? "      Kpps         Mbps           cnt"
        : "      Kpps         Mbps";
    if (!(flags & F_LIST_NOHEADER)) {
        n += sprintf(&str[n], "\n\n\n\n");
        n += sprintf(&str[n], "%-*s  %-*s    %s\n",
            16, "Interface", w, "Receive", "Transmit");
        n += sprintf(&str[n], "%-*s  %-*s    %s\n",
            16, "", w, head, head);
    }
    return n;
}

/*
 * It is possible to skip over interfaces with no active traffic
 */
static inline int
ifaceFilter (
    const sample_t *sp0, const sample_t *sp1,
    float f,
    int flags,
    int min_bit_rate, int min_pkt_rate)
{
    if ((flags & F_LIST_IGNZERO) && ifaceZero(&sp1->r, &sp1->t))
        return -1;
    if (min_pkt_rate > 0) {
        int t_pkt_rate = (int) (f * ((float) (sp1->t.pkt - sp0->t.pkt)));
        int r_pkt_rate = (int) (f * ((float) (sp1->r.pkt - sp0->r.pkt)));
        if ((t_pkt_rate < min_pkt_rate) && (r_pkt_rate < min_pkt_rate))
            return -1;
    }
    if (min_bit_rate > 0) {
        int t_bit_rate = (int) (f * (float) (sp1->t.oct - sp0->t.oct) * 8.0);
        int r_bit_rate = (int) (f * (float) (sp1->r.oct - sp0->r.oct) * 8.0);
        if ((t_bit_rate < min_bit_rate) & (r_bit_rate < min_bit_rate))
            return -1;
    }
    return 0;
}

int printIfaceLine (char *str,
    const sample_t *sp0, const sample_t *sp1,
    const ifdata_t *ifp,
    int flags,
    int min_bit_rate, int min_pkt_rate)
{
    uint32_t usec =
        (sp1->tv0.tv_sec - sp0->tv0.tv_sec) * 1000000 +
        (sp1->tv0.tv_usec - sp0->tv0.tv_usec);
    float f = (usec == 0) ? 0.0 : (1e6 / ((float) usec));

    if (ifaceFilter(sp0, sp1, f, flags, min_bit_rate, min_pkt_rate) < 0)
        return 0;

    int n = 0;
    n += printCntSet(0, flags, &str[n],
        &sp0->r, &sp1->r, f, ifp->ref.r);
    n += sprintf(&str[n], "    ");
    n += printCntSet(0, flags, &str[n],
        &sp0->t, &sp1->t, f, ifp->ref.t);
    return n;
}

static ifdata_t *
ifdata_alloc (int type, const char *ifname)
{
    ifdata_t *p = (ifdata_t *) malloc(sizeof(ifdata_t));
    memset(p, 0, sizeof(ifdata_t));
    p->type = type;
    switch (type) {
      case TOTAL:
      case TOTAL_RESET:
        p->ifname = "TOTAL";
        break;
      default:
        p->ifname = ifname;
        break;
    }
    return p;
}

int
main (int argc, char *argv[]) {
    char str[512];
    int flags = 0;
    int ifcnt = 0;
    int i, x = 1, y = 0;
    int ifidx;
    int ival = 500000;
    int hist = 5;
    int min_pkt_rate = 0;
    int min_bit_rate = 0;
    ifdata_t *ifdata[512];
    char buf[65536];
    // Running total entry pointer
    ifdata_t *tp;

    // Default Total Entry
    ifdata[ifcnt++] = ifdata_alloc(TOTAL_RESET, NULL);

    for (i=1 ; i < argc ; i++) {
        char *a = argv[i];
        if ((strcmp(a, "-h") == 0) || (strcmp(a, "--help") == 0))
            goto Usage;
        if ((strcmp(a, "-i") == 0) || (strcmp(a, "--interval") == 0))
            ival = (int) (1e6 * atof(argv[++i]));
        else if (strcmp(a, "--hist") == 0)
            hist = (int) (1e6 * atof(argv[++i]));
        else if (strcmp(a, "--long") == 0)
            flags |= F_LIST_COUNT;
        else if (strcmp(a, "--count") == 0)
            flags |= F_LIST_COUNT;
        else if (strcmp(a, "--list-drop") == 0)
            flags |= F_LIST_DROP;
        else if (strcmp(a, "--reset") == 0)
            flags |= F_LIST_REF;
        else if (strcmp(a, "--ignore-zero") == 0)
            flags |= F_LIST_IGNZERO;
        else if (strcmp(a, "--ignore-missing") == 0)
            flags |= F_LIST_IGNMISSING;
        else if (strcmp(a, "--total-start") == 0)
            ifdata[ifcnt++] = ifdata_alloc(TOTAL_RESET, NULL);
        else if (strcmp(a, "--space") == 0)
            ifdata[ifcnt++] = ifdata_alloc(SPACE, NULL);
        else if (strcmp(a, "--total") == 0)
            ifdata[ifcnt++] = ifdata_alloc(TOTAL, NULL);
        else if (strcmp(a, "--once") == 0)
            flags |= F_LIST_ONCE;
        else if (strcmp(a, "--no-header") == 0)
            flags |= F_LIST_NOHEADER;
        else if (strcmp(a, "--norm") == 0)
            flags |= F_LIST_NORM;
        else if (strcmp(a, "--pktsize") == 0)
            flags |= F_LIST_PKTSIZE;
        else if (strcmp(a, "--min-pkt-rate") == 0)
            min_pkt_rate = atoi(argv[++i]);
        else if (strcmp(a, "--min-bit-rate") == 0)
            min_bit_rate = atoi(argv[++i]);
        else {
            ifdata_t *p = ifdata_alloc(IFACE, strdup(a));
            ifdata[ifcnt++] = p;
        }
    }
    if (ifcnt == 0) {
      Usage:
        printf("%s [--help] [--once] [--long] "
            "[--list-long] [--reset] [-i <interval [s]>] "
            "[--no-header] [--norm] [--pktsize] "
            "[--total-start] [--total]"
            "[-n] <interface> [...]\n",
            argv[0]);
        return 0;
    }

    for (ifidx = 0, tp = NULL ; ifidx < ifcnt ; ifidx++) {
        ifdata_t *p = ifdata[ifidx];
        int rc;
        switch (p->type) {
          case IFACE:
            rc = sample(p->ifname, &p->ref);
            if (rc != 1) {
                if (flags & F_LIST_IGNMISSING) {
                    continue;
                }
                printf("ERROR: could not sample interface %s\n", p->ifname);
                goto Usage;
            }
            p->smpl[0] = p->ref;
            if (tp != NULL) {
                sample_aggregate(&tp->ref, &p->ref);
                tp->smpl[0] = tp->ref;
            }
            break;
          case TOTAL_RESET:
          case TOTAL:
            tp = p;
            memset(&tp->smpl[0], 0, sizeof(sample_t));
            memset(&tp->ref, 0, sizeof(sample_t));
            break;
        }
    }

    for (;;) {
        usleep(ival);

        for (ifidx = 0, tp = NULL ; ifidx < ifcnt ; ifidx++) {
            ifdata_t *p = ifdata[ifidx];
            sample_t *sp = p->smpl;
            switch (p->type) {
              case IFACE:
                sample(p->ifname, &sp[x]);
                if (tp != NULL) {
                    sample_aggregate(&tp->smpl[x], &sp[x]);
                }
                break;
              case TOTAL_RESET:
              case TOTAL:
                tp = p;
                memset(&tp->smpl[x], 0, sizeof(sample_t));
                break;
            }
        }

        int n = printHeader(buf, flags);

        for (ifidx = 0, tp = NULL ; ifidx < ifcnt ; ifidx++) {
            int rc;
            ifdata_t *p = ifdata[ifidx];
            sample_t *sp = p->smpl;
            switch (p->type) {
              case IFACE:
                rc = printIfaceLine(str, &sp[y], &sp[x], p, flags,
                    min_bit_rate, min_pkt_rate);
                if (rc > 0) {
                    n += sprintf(&buf[n], "%-16s  %s\n", p->ifname, str);
                }
                break;
              case TOTAL_RESET:
                tp = p;
                break;
              case TOTAL:
                if (tp != NULL) {
                    sp = tp->smpl;
                    printIfaceLine(str, &sp[y], &sp[x], tp, flags, 0, 0);
                    n += sprintf(&buf[n], "%-16s  %s\n", tp->ifname, str);
                }
                tp = p;
                break;
              case SPACE:
                n += sprintf(&buf[n], "\n");
                break;
            }
        }

        /* Print the entire section in one chunk in order to minimize flicker */
        printf("%s", buf);
        fflush(stdout);

        if (flags & F_LIST_ONCE)
            break;

        x = (x + 1) % 5;
        if (x == y)
            y = (y + 1) % 5;
    }

    return 0;
}
