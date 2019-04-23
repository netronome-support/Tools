#ifndef __DPDK_RATELIMIT_H__
#define __DPDK_RATELIMIT_H__

#include <stdint.h>

#define FRAC_SHIFT (32)

typedef struct {
    /* Amount of fractional credits per TSC tick */
    uint64_t f_tick_quota;
    /* Accumulation of fractional credits */
    uint64_t f_credits;
    /* Last update of 'credits' */
    uint64_t tsc_last;
    /* Max accumulation of credits */
    uint64_t f_max_credits;
} rate_limit_t;

static inline int
rate_limit_get_credit (rate_limit_t *rlp)
{
    uint32_t tsc = rte_rdtsc();
    uint32_t diff = tsc - rlp->tsc_last;
    uint64_t fc = rlp->f_credits + ((uint64_t) diff * rlp->f_tick_quota);
    if (unlikely(fc > rlp->f_max_credits)) {
        fc = rlp->f_max_credits;
    }
    rlp->tsc_last = tsc;
    rlp->f_credits = fc;
    return fc >> FRAC_SHIFT;
}

static inline void
rate_limit_update (rate_limit_t *rlp, int credits)
{
    rlp->f_credits -= ((uint64_t) credits << FRAC_SHIFT);
}

static inline void
rate_limit_setup (rate_limit_t *rlp,
    double rate,        /* Credits per second */
    uint32_t max_burst) /* Max accumulated credit build-up */
{
    rlp->tsc_last = rte_rdtsc();
    rlp->f_credits = 0;
    rlp->f_tick_quota = (uint64_t) (rate / ((double) rte_get_tsc_hz())
        * (double) ((uint64_t) 1 << FRAC_SHIFT));
    rlp->f_max_credits = (uint64_t) max_burst << FRAC_SHIFT;
}

#endif
