#ifndef __RT_PORT_H__
#define __RT_PORT_H__

#include <stdint.h>
#include <stdio.h>

#include "defines.h"

extern FILE *log_fd;

/* Port Information */
typedef struct {
    port_index_t        idx;
    uint8_t             flags;
    eth_addr_t          hwaddr;
    ipv4_addr_t         ipaddr;
    void                *tx_buffer;
    /* Queue count */
    uint8_t             rx_q_count;
    uint8_t             tx_q_count;
    /* Per-Queue Descriptor Counts */
    int                 rx_desc_cnt;
    int                 tx_desc_cnt;
    lcore_id_t          rx_lcore;
    lcore_id_t          tx_lcore;
} port_info_t;

#define PORT_F_EXIST         (1 << 0)
#define PORT_F_PROMISC       (1 << 1)
#define PORT_F_GRATARP       (1 << 2)

#define PORT_LCORE_UNASSIGNED    (255)

#define PORT_DIR_UNDEF   0
#define PORT_DIR_RX      1
#define PORT_DIR_TX      2

extern port_info_t port_table[MAX_PORT_COUNT];

#define FOREACH_PORT(prtidx) \
    for (port_index_t  prtidx = 0 ; prtidx < MAX_PORT_COUNT ; prtidx++) \
        if (port_enabled(prtidx))

static inline port_info_t *
port_lookup (port_index_t prtidx)
{
    assert(prtidx < MAX_PORT_COUNT);
    return &port_table[prtidx];
}

void port_set_ipv4_addr (port_index_t port, ipv4_addr_t addr,
    int len);

void port_set_ip_addr (port_index_t port,
    const char *str, int len);

void port_dump_info (port_index_t prtidx);
void port_assign_thread (int prtidx, int direction, lcore_id_t lcore);
void lcore_default_assign (int dir);
int port_check_lcores (void);
void log_port_lcore_assignment (void);
void port_periodic (void);

void port_table_init (void);

/* port-setup.c */
int port_setup (void);
int port_desc_count (void);
void check_all_ports_link_status (void);

#endif
