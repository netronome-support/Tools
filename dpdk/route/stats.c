#include <stdio.h>
#include <inttypes.h>

#include "stats.h"

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
    printf("\nLoad: ");
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
    uint64_t total_packets_dropped, total_packets_tx, total_packets_rx;
    unsigned portid;

    total_packets_dropped = 0;
    total_packets_tx = 0;
    total_packets_rx = 0;

    const char clr[] = { 27, '[', '2', 'J', '\0' };
    const char topLeft[] = { 27, '[', '1', ';', '1', 'H','\0' };

    /* Clear screen and move to top left */
    printf("%s%s", clr, topLeft);

    printf("\nPort statistics ====================================");

    for (portid = 0; portid < RTE_MAX_ETHPORTS; portid++) {
        /* skip disabled ports */
        if (!port_enabled(portid))
            continue;
        printf("\nStat_istics for port %u ------------------------------"
               "\nPackets sent: %24"PRIu64
               "\nPackets received: %20"PRIu64
               "\nPackets dropped: %21"PRIu64,
               portid,
               port_statistics[portid].tx,
               port_statistics[portid].rx,
               port_statistics[portid].dropped);
        print_load_statistics(portid);
        total_packets_dropped += port_statistics[portid].dropped;
        total_packets_tx += port_statistics[portid].tx;
        total_packets_rx += port_statistics[portid].rx;
    }
    printf("\nAggregate statistics ==============================="
           "\nTotal packets sent: %18"PRIu64
           "\nTotal packets received: %14"PRIu64
           "\nTotal packets dropped: %15"PRIu64,
           total_packets_tx,
           total_packets_rx,
           total_packets_dropped);
    printf("\n====================================================\n");
}

