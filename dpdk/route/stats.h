#ifndef __RT_STATS_H__
#define __RT_STATS_H__

#include "defines.h"

typedef int rt_cnt_idx_t;

#define LS_EMPTY    0
#define LS_SINGLE   1
#define LS_PARTIAL  2
#define LS_FULL     3
#define LS_PKTCNT   4
#define LS_COUNTERS 5

struct load_statistics {
        uint64_t cnt[LS_COUNTERS];
};

/* Per-port statistics struct */
struct rt_port_statistics {
    uint64_t rx;
    uint64_t tx;
    uint64_t qfull;
    uint64_t disc;
    uint64_t error;
    uint64_t term;
    struct load_statistics ls, prev;
} __rte_cache_aligned;

extern struct rt_port_statistics port_statistics[RTE_MAX_ETHPORTS];

static inline void
update_load_statistics (int portid, int rx_pkt_cnt)
{
    int offset;
    if (rx_pkt_cnt == 0) {
        offset = LS_EMPTY;
    } else if (rx_pkt_cnt == 1) {
        offset = LS_SINGLE;
    } else if (rx_pkt_cnt < MAX_PKT_BURST) {
        offset = LS_PARTIAL;
        port_statistics[portid].ls.cnt[LS_PKTCNT] += rx_pkt_cnt;
    } else {
        offset = LS_FULL;
    }
    port_statistics[portid].ls.cnt[offset]++;
}

static int aaaa = 0;

static inline void
rt_stats_incr (rt_cnt_idx_t cntidx)
{
    aaaa = cntidx; // dummy
}

void print_load_statistics (int prtidx);
void print_stats (void);
void rt_stats_init (void);

#endif
