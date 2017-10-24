#ifndef __RT_PORT_H__
#define __RT_PORT_H__

#include <stdint.h>

#include "stats.h"
#include "defines.h"

#define RT_RD_DEFAULT (1)

#include <stdio.h>
extern FILE *rt_log_fd;

/* DHCP Port Information */
typedef struct {
  uint8_t           state;
  uint32_t          transaction;
  rt_ipv4_addr_t    srv_ipaddr;
  rt_ipv4_addr_t    offer_ipv4_addr;
} rt_dhcp_info_t;

/* Port Information */
typedef struct {
  rt_port_index_t   idx;
  rt_rd_t           rdidx;
  uint8_t           flags;
  rt_eth_addr_t     hwaddr;
  rt_ipv4_prefix_t  prefix;
  rt_ipv4_addr_t    ipaddr;
  void              *tx_buffer;
  rt_cnt_idx_t      cntidx;
  rt_dhcp_info_t    dhcpinfo;
} rt_port_info_t;

#define RT_PORT_F_EXIST         (1 << 0)
#define RT_PORT_F_PROMISC       (1 << 1)

#define RT_PORT_MAX 128
extern rt_port_info_t rt_port_table[RT_PORT_MAX];

static inline rt_port_info_t *
rt_port_lookup (rt_port_index_t port)
{
    assert(port < RT_PORT_MAX);
    return &rt_port_table[port];
}

void rt_port_create (rt_port_index_t port, void *hwaddr,
    void *tx_buffer);

void rt_port_set_routing_domain (rt_port_index_t port, rt_rd_t rdidx);

void rt_port_set_ipv4_addr (rt_port_index_t port, rt_ipv4_addr_t addr,
    int len);

void rt_port_set_ip_addr (rt_port_index_t port,
    const char *str, int len);

extern void rt_port_table_init (void);

#endif
