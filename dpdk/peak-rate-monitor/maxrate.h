#ifndef __MAX_RATE_H
#define __MAX_RATE_H

#include <stdint.h>

typedef struct {
    uint64_t tick;      /* DPDK TSC clock */
    uint64_t pkt;
    uint64_t oct;
} sample_t;

typedef struct {
    double pkt;
    double oct;
} rate_t;

#define SAMPLE_WHEEL_COUNT            8
#define SAMPLE_WHEEL_SIZE   (1024*1024)
#define SAMPLE_MAX_RATES              2
#define SAMPLE_MAX_0_COUNT           50
#define SAMPLE_MAX_1_COUNT          200
typedef struct {
    sample_t s[SAMPLE_WHEEL_SIZE];
    uint64_t idx; /* current position */
    rate_t max[2];
} sample_wheel_t;

#define MAX_MONITOR_CNT              32
typedef struct {
    int prtidx;
    double window; /* Minimum time window for rate calculation [s] */
    uint64_t ticks; /* Minimum time window in TSC ticks */
    uint64_t trail; /* Trailing index in sample wheel */
    rate_t maxrate;
    double dampening; /* Factor to reduce the maxrate each print-period */
    /* Extra information collected when saving a 'max rate' */
    struct {
        uint32_t bursts;
        uint32_t packets;
    } oct, pkt;
} monitor_t;

/**********************************************************************/

void maxrate_add_monitor_args (const char *argstr);
void maxrate_print_monitors (void);

void maxrate_print_header (void);
void maxrate_print_rates (int prtidx);

void maxrate_save_sample (int prtidx,
    uint64_t tick,      /* Current TSC clock tick */
    uint64_t lbgt,      /* Last Background Action (in TSC tick) */
    uint64_t pkt,       /* Port packet counter */
    uint64_t oct);      /* Port byte counter */

void maxrate_init (void);

#endif
