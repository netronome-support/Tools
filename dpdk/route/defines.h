#ifndef __RT_DEFINES_H__
#define __RT_DEFINES_H__

#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#define max(a,b) (((a) > (b)) ? (a) : (b))
#define min(a,b) (((a) < (b)) ? (a) : (b))

/* Network Byte Order Ethernet Hardware (MAC) Address */
//typedef uint64_t rt_eth_addr_t;
typedef uint8_t rt_eth_addr_t[6];

typedef uint16_t rt_port_index_t;

typedef uint32_t rt_ipv4_addr_t;

typedef struct {
    rt_ipv4_addr_t addr;
    uint8_t len;
} rt_ipv4_prefix_t;

/* Routing Domain Index */
typedef uint16_t rt_rd_t;

/* Global Variables */
typedef struct {
    int ping_nexthops;
    int print_statistics;
    /* A tsc-based timer responsible for triggering statistics printout */
    uint64_t timer_period;
    /* mask of enabled ports */
    uint64_t enabled_port_mask;
    int rx_queue_per_lcore;
    uint64_t rand_disc_level;
} rt_global_t;

extern rt_global_t g;

static inline int
port_enabled (int prtidx)
{
    return (g.enabled_port_mask & (1LU << prtidx)) != 0;
}

static inline void
rt_global_init (void)
{
    memset(&g, 0, sizeof(g));
    g.print_statistics = 1;
    g.timer_period = 2; /* default period is 10 seconds */
    g.rx_queue_per_lcore = 1;
}

#define MAX_RX_QUEUE_PER_LCORE 16
#define MAX_TX_QUEUE_PER_PORT 16

#define MAX_TIMER_PERIOD 86400 /* 1 day max */

#endif
