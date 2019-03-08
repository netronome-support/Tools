#ifndef __RT_PORT_H__
#define __RT_PORT_H__

#include <stdint.h>
#include <stdio.h>

#include "stats.h"
#include "defines.h"

#define RT_RD_DEFAULT (1)

extern FILE *rt_log_fd;

/* Queue Descriptor */
typedef struct {
    rt_port_index_t     prtidx;
    rt_queue_index_t    queidx;
} rt_queue_t;

/* DHCP Port Information */
typedef struct {
    uint8_t             state;
    uint32_t            transaction;
    rt_ipv4_addr_t      srv_ipaddr;
    rt_ipv4_addr_t      offer_ipv4_addr;
} rt_dhcp_info_t;

/* Port Information */
typedef struct {
    rt_port_index_t     idx;
    rt_rd_t             rdidx;
    uint8_t             flags;
    rt_eth_addr_t       hwaddr;
    rt_ipv4_prefix_t    prefix;
    rt_ipv4_addr_t      ipaddr;
    void                *tx_buffer;
    /* Queue count */
    uint8_t             rx_q_count;
    uint8_t             tx_q_count;
    /* Per-Queue Descriptor Counts */
    int                 rx_desc_cnt;
    int                 tx_desc_cnt;
    rt_cnt_idx_t        cntidx;
    rt_dhcp_info_t      dhcpinfo;
    rt_lcore_id_t       rx_lcore;
    rt_lcore_id_t       tx_lcore;
} rt_port_info_t;

/* Per-Thread Queue List to process on RX */
typedef struct {
    int count;
    rt_queue_t list[0];
} rt_queue_list_t;

#define RT_PORT_F_EXIST         (1 << 0)
#define RT_PORT_F_PROMISC       (1 << 1)
#define RT_PORT_F_GRATARP       (1 << 2)

#define RT_PORT_LCORE_UNASSIGNED    (255)

#define RT_PORT_DIR_UNDEF   0
#define RT_PORT_DIR_RX      1
#define RT_PORT_DIR_TX      2

extern rt_port_info_t rt_port_table[RT_MAX_PORT_COUNT];

#define FOREACH_PORT(prtidx) \
    for (rt_port_index_t  prtidx = 0 ; prtidx < RT_MAX_PORT_COUNT ; prtidx++) \
        if (port_enabled(prtidx))

static inline rt_port_info_t *
rt_port_lookup (rt_port_index_t prtidx)
{
    assert(prtidx < RT_MAX_PORT_COUNT);
    return &rt_port_table[prtidx];
}

void rt_port_set_routing_domain (rt_port_index_t port, rt_rd_t rdidx);

void rt_port_set_ipv4_addr (rt_port_index_t port, rt_ipv4_addr_t addr,
    int len);

void rt_port_set_ip_addr (rt_port_index_t port,
    const char *str, int len);

void rt_port_dump_info (rt_port_index_t prtidx);
void rt_port_assign_thread (int prtidx, int direction, rt_lcore_id_t lcore);
void rt_lcore_default_assign (int dir);
rt_queue_list_t *create_thread_rx_queue_list (rt_lcore_id_t lcore);
int rt_port_check_lcores (void);
void log_port_lcore_assignment (void);
void rt_port_periodic (void);

void rt_port_table_init (void);

/* port-setup.c */
int rt_port_setup (void);
int rt_port_desc_count (void);
void rt_check_all_ports_link_status (void);

#endif
