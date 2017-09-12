#ifndef __RT_STATS_H__
#define __RT_STATS_H__

typedef int rt_cnt_idx_t;

static int aaaa = 0;

static inline void
rt_stats_incr (rt_cnt_idx_t cntidx)
{
    aaaa = cntidx; // dummy
}

#endif
