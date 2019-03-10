#include <stdio.h>
#include <inttypes.h>

#include "stats.h"
#include "port.h"

rt_port_stats_t port_statistics[RTE_MAX_ETHPORTS];

void
print_load_statistics (int prtidx)
{
    rt_load_stats_t delta;
    rt_load_stats_t *nlsp = &port_statistics[prtidx].ls;
    rt_load_stats_t *olsp = &port_statistics[prtidx].prev;
    uint64_t total = 0;
    int i;
    for (i = 0 ; i < LS_COUNTERS ; i++ ) {
        delta.cnt[i] = nlsp->cnt[i] - olsp->cnt[i];
        total += delta.cnt[i];
    }
    printf("  %3u: ", prtidx);
    for (i = 0 ; i < LS_COUNTERS ; i++ ) {
        char numstr[32] = "";
        if (total > 0) {
            sprintf(numstr, "%5.1f%%", 100.0 * 
                ((double) delta.cnt[i]) / ((double) total));
        }
        printf(" %c: %-6s%s", ("ESPF")[i], numstr,
            (i < (LS_COUNTERS - 1)) ? ", " : ""
        );
    }
    if (nlsp->cnt[LS_PARTIAL] > 0) {
        printf("  avg=%.1f  ",
            (double) nlsp->cnt[LS_PKTCNT] 
            / (double) nlsp->cnt[LS_PARTIAL]);
    }
    for (i = 0 ; i < LS_COUNTERS ; i++ ) {
        olsp->cnt[i] = nlsp->cnt[i];
    }
    printf("\n");
}

/* Print out statistics on packets dropped */
void
print_stats (void)
{
    int idx;
    rt_port_stats_t ts;
    memset(&ts, 0, sizeof(ts));

    const char clr[] = { 27, '[', '2', 'J', '\0' };
    const char topLeft[] = { 27, '[', '1', ';', '1', 'H','\0' };

    /* Clear screen and move to top left */
    printf("%s%s", clr, topLeft);

    printf("\n==  Statistics  ========================================="
        "=================\n");

    printf("%5s%12s%12s%9s%9s%9s%9s%9s\n",
        "Port", "RX", "TX", "QFULL", "DROP", "TERM", "ERROR", "IGNORE");     

    #define fmt_l "%12"PRIu64
    #define fmt_s "%9"PRIu64
    #define fmt fmt_l fmt_l fmt_s fmt_s fmt_s fmt_s

    FOREACH_PORT(prtidx) {
        /* skip disabled ports */
        rt_port_stats_t *ps = &port_statistics[prtidx];
        printf("%5u" fmt_l fmt_l, prtidx, ps->rx, ps->tx);
        for (idx = 0 ; idx < RT_DISC_REASONS ; idx++) {
            printf(fmt_s, ts.disc[idx]);
            ts.disc[idx] += ps->disc[idx];
        }
        ts.rx       += ps->rx;
        ts.tx       += ps->tx;
        printf("\n");
    }
    printf("%5s" fmt_l fmt_l, "TOTAL",
        ts.rx, ts.tx);
    for (idx = 0 ; idx < RT_DISC_REASONS ; idx++)
        printf(fmt_s, ts.disc[idx]);
    printf("\n");

    printf("==========================================================="
        "===============\n");

    FOREACH_PORT(prtidx) {
        print_load_statistics(prtidx);
    }

    printf("==========================================================="
        "===============\n");
}

void rt_stats_init (void)
{
    memset(&port_statistics, 0, sizeof(port_statistics));
}

