#ifndef __RT_TABLES_H__
#define __RT_TABLES_H__

#include <stdint.h>
#include <stdio.h>

#include "stats.h"
#include "defines.h"
#include "port.h"
#include "pktutils.h"
#include "port.h"

typedef struct rt_dt_route_s {
  struct rt_dt_route_s *prev, *next;
  rt_port_info_t *pi;
  rt_ipv4_addr_t ipaddr;
  rt_rd_t rdidx;
  rt_port_index_t port;
  uint8_t flags;
  void *tx_buffer;
  struct {
    rt_eth_addr_t *dst;
    rt_eth_addr_t src;
  } eth;
  rt_cnt_idx_t cntidx;
} rt_dt_route_t;

#define RT_DT_F_LOCAL           (1 << 0)
#define RT_DT_F_DISCARD         (1 << 1)

/* Linear List of Route Data Entries */
typedef struct rt_lpm_s {
  struct rt_lpm_s *prev, *next;
  rt_rd_t rdidx;
  rt_ipv4_prefix_t prefix;
  uint32_t flags;
  rt_port_info_t *pi; /* Egress Port Information */
  rt_eth_addr_t hwaddr;
  rt_ipv4_addr_t nhipa;
  rt_rd_t nh_rdidx;
  struct rt_lpm_s *nh; /* Next Hop */
  rt_pkt_t pkt; /* Pending Packet for Address Resolution */
  rt_cnt_idx_t cntidx;
} rt_lpm_t;

#define RT_LPM_F_HAS_HWADDR     (1 << 0)
#define RT_LPM_F_LOCAL          (1 << 1)
#define RT_LPM_F_HAS_PACKET     (1 << 2)
#define RT_LPM_F_HAS_NEXTHOP    (1 << 3)
#define RT_LPM_F_HAS_PORTINFO   (1 << 4)
#define RT_LPM_F_IS_NEXTHOP     (1 << 5)
#define RT_LPM_F_DISCARD        (1 << 6)

#define RT_DT_SIZE 65535
extern rt_dt_route_t dt[RT_DT_SIZE];

static inline uint32_t
rt_dt_hash (rt_rd_t rd, rt_ipv4_addr_t addr)
{
    uint32_t idx = addr + (addr >> 7) + (addr >> 14) + (addr >> 21)
        + (rd << 3);
    return idx % RT_DT_SIZE;
}

static inline rt_dt_route_t *
rt_dt_lookup (rt_rd_t rdidx, rt_ipv4_addr_t ipaddr)
{
    uint32_t idx = rt_dt_hash(rdidx, ipaddr);
    rt_dt_route_t *hd = &dt[idx];

    if (likely((hd->rdidx == rdidx) && (hd->ipaddr == ipaddr)))
        return hd;

    rt_dt_route_t *sp = hd->next;
    while (likely(sp != hd)) {
        if ((sp->rdidx == rdidx) && (sp->ipaddr == ipaddr))
            return sp;
        sp = sp->next;
    }
    return NULL;
}

rt_dt_route_t *rt_dt_lookup (rt_rd_t vifidx, rt_ipv4_addr_t addr);
extern void rt_dt_create (rt_rd_t rdidx, rt_ipv4_addr_t addr,
    rt_lpm_t *, uint8_t flags);
extern void rt_dt_init (void);
extern int rt_dt_sprintf (char *str, const rt_dt_route_t *dt);
extern void rt_dt_dump (FILE *fd);

rt_lpm_t *rt_lpm_lookup (rt_rd_t rdidx, rt_ipv4_addr_t addr);
rt_lpm_t *rt_lpm_find_or_create (rt_rd_t rdidx,
    rt_ipv4_prefix_t prefix, rt_port_info_t *pi);
rt_lpm_t *rt_lpm_route_create (rt_rd_t rdidx, rt_ipv4_addr_t ipaddr, int plen,
    uint32_t flags, rt_ipv4_addr_t nhipa, rt_rd_t nh_rdidx);
rt_lpm_t *rt_lpm_add_nexthop (rt_rd_t rdidx, rt_ipv4_addr_t ipaddr);

static inline rt_lpm_t *
rt_lpm_host_create (rt_rd_t rdidx, rt_ipv4_addr_t ipaddr,
    rt_port_info_t *pi, uint32_t flags)
{
    rt_ipv4_prefix_t prefix;
    prefix.addr = ipaddr;
    prefix.len = 32;
    rt_lpm_t *rt = rt_lpm_find_or_create(rdidx, prefix, pi);
    if (rt != NULL)
        rt->flags |= flags;
    return rt;
}

static inline int
rt_lpm_is_host_route (const rt_lpm_t *rt)
{
    return (rt->prefix.len == 32);
}

static inline void
rt_lpm_set_hwaddr (rt_lpm_t *rt, rt_eth_addr_t hwaddr)
{
    memcpy(rt->hwaddr, hwaddr, 6);
    rt->flags |= RT_LPM_F_HAS_HWADDR;
}

extern void rt_lpm_table_init (void);
extern int rt_lpm_sprintf (char *str, const rt_lpm_t *rt);
extern void rt_lpm_dump (FILE *);
void rt_lpm_gen_icmp_requests (void);

#endif
