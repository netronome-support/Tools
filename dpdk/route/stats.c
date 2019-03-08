#include <stdio.h>
#include <inttypes.h>

#include "stats.h"
#include "port.h"

struct rt_port_statistics port_statistics[RTE_MAX_ETHPORTS];

void
print_load_statistics (int prtidx)
{
    struct load_statistics delta;
    struct load_statistics *nlsp = &port_statistics[prtidx].ls;
    struct load_statistics *olsp = &port_statistics[prtidx].prev;
    uint64_t total = 0;
    int i;
    for (i = 0 ; i < LS_COUNTERS ; i++ ) {
        delta.cnt[i] = nlsp->cnt[i] - olsp->cnt[i];
        total += delta.cnt[i];
    }
    printf("Load %3u:  ", prtidx);
    for (i = 0 ; i < 4 ; i++ ) {
        char numstr[32] = "";
        if (total > 0) {
            sprintf(numstr, "%5.1f%%", 100.0 * 
                ((double) delta.cnt[i]) / ((double) total));
        }
        printf("  %c: %-6s%s", ("ESPF")[i], numstr,
            (i < (LS_COUNTERS - 1)) ? ", " : ""
        );
    }
    if (nlsp->cnt[LS_PARTIAL] > 0) {
        printf("  avg=%.1f  ",
            (double) nlsp->cnt[LS_PKTCNT] 
            / (double) nlsp->cnt[LS_PARTIAL]);
    }
    printf("\n");
}

/* Print out statistics on packets dropped */
void
print_stats (void)
{
    struct rt_port_statistics ts;
    memset(&ts, 0, sizeof(ts));

    const char clr[] = { 27, '[', '2', 'J', '\0' };
    const char topLeft[] = { 27, '[', '1', ';', '1', 'H','\0' };

    /* Clear screen and move to top left */
    printf("%s%s", clr, topLeft);

    printf("\n==  Statistics  ========================================="
        "===============\n");

    printf("%8s%12s%12s%10s%10s%10s%10s\n",
        "Port", "RX", "TX", "QFULL", "ERROR", "DISC", "TERM");     

    #define fmt_l "%12"PRIu64
    #define fmt_s "%10"PRIu64
    #define fmt fmt_l fmt_l fmt_s fmt_s fmt_s fmt_s

    FOREACH_PORT(prtidx) {
        /* skip disabled ports */
        struct rt_port_statistics *ps = &port_statistics[prtidx];
        printf("%8u" fmt "\n", prtidx,
            ps->rx, ps->tx, ps->qfull, ps->error, ps->disc, ps->term);
        ts.rx       += ps->rx;
        ts.tx       += ps->tx;
        ts.qfull    += ps->qfull;
        ts.error    += ps->error;
        ts.disc     += ps->disc;
        ts.term     += ps->term;
    }
    printf("%8s" fmt "\n", "TOTAL",
        ts.rx, ts.tx, ts.qfull, ts.error, ts.disc, ts.term);

    printf("==========================================================="
        "=============\n");

    FOREACH_PORT(prtidx) {
        print_load_statistics(prtidx);
    }

    printf("==========================================================="
        "=============\n");
}

void rt_stats_init (void)
{
    memset(&port_statistics, 0, sizeof(port_statistics));
}

