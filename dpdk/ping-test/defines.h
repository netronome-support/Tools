#ifndef __RT_DEFINES_H__
#define __RT_DEFINES_H__

#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdbool.h>

#define max(a,b) (((a) > (b)) ? (a) : (b))
#define min(a,b) (((a) < (b)) ? (a) : (b))

#define MAX_PKT_BURST 64

#define MAX_PORT_COUNT 32

#define RTE_RX_DESC_DEFAULT 2048
#define RTE_TX_DESC_DEFAULT 2048

#define RTE_MBUF_DESC_MARGIN 16384

/* Network Byte Order Ethernet Hardware (MAC) Address */
typedef uint8_t eth_addr_t[6];

typedef uint16_t port_index_t;
typedef uint8_t queue_index_t;
typedef uint8_t lcore_id_t;

typedef uint32_t ipv4_addr_t;

/* Global Variables */
typedef struct {
    bool force_quit;
    bool have_hwaddr;
    bool measure_latency;
    port_index_t prtidx;
    ipv4_addr_t l_ipv4_addr;
    ipv4_addr_t r_ipv4_addr;
    eth_addr_t l_hwaddr;
    eth_addr_t r_hwaddr;
    char *dump_fname;
    double duration;
    double rate;
    int pktsize;
    uint64_t count;
    struct rte_eth_dev_tx_buffer *buffer;
} global_t;

extern global_t g;

static inline int
port_enabled (int prtidx)
{
    return ((1 << g.prtidx) & (1LU << prtidx)) != 0;
}

static inline void
global_init (void)
{
    memset(&g, 0, sizeof(g));
    g.duration = 0.0;
    g.rate = 1.0;
    g.pktsize = 14 + 20 + 8 + 8;
    g.count = 0;
}

typedef struct {
    uint64_t tx_pkt_cnt;
    uint64_t rx_pkt_cnt;
    uint64_t out_of_order;
    /* Sequence Numbers */
    uint16_t tx_seq_num; /* For last generated ICMP */
    uint16_t rx_seq_num; /* For most recently received ICMP */
} icmp_stats_t;

extern icmp_stats_t icmp_stats;

#define MAX_RX_QUEUE_PER_LCORE 16
#define MAX_TX_QUEUE_PER_PORT 16

#define MAX_TIMER_PERIOD 86400 /* 1 day max */

#endif
