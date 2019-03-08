#ifndef __RT_TABLES_H__
#define __RT_TABLES_H__

#include <stdint.h>
#include <stdio.h>

#include "stats.h"
#include "defines.h"
#include "port.h"
#include "pktutils.h"
#include "port.h"

/**********************************************************************/
/* Forwarding Flags */

#define RT_FWD_F_DISCARD        (1 << 0)
#define RT_FWD_F_RANDDISC       (1 << 1)

#define RT_FWD_F_MASK           (0xff)
/**********************************************************************/

typedef struct __attribute__ ((__packed__)) {
    rt_ipv4_addr_t ipaddr; /* Forwarding IPv4 address */
    rt_port_index_t prtidx; /* Receive Port */
    rt_eth_addr_t hwaddr; /* Local MAC address */
} rt_dt_key_t;

typedef struct rt_dt_route_s {
    struct rt_dt_route_s *prev, *next;
    rt_dt_key_t key;
    rt_port_info_t *pi;
    rt_port_index_t port;
    uint8_t flags;
    void *tx_buffer;
    struct {
        rt_eth_addr_t dst;
        rt_eth_addr_t src;
    } eth;
    rt_cnt_idx_t cntidx;
} rt_dt_route_t;

/**********************************************************************/
/* Linear List of Route Data Entries */

typedef struct rt_lpm_s {
    struct rt_lpm_s *prev, *next;
    /* Key */
    rt_rd_t rdidx;
    rt_ipv4_prefix_t prefix;
    /* Result */
    uint32_t flags;
    rt_port_info_t *pi; /* Egress Port Information */
    union {
        /* Next-hop IP address */
        rt_ipv4_addr_t nhipa;
        /* For subnet routes: Inteface IP address */
        rt_ipv4_addr_t ifipa;
    };
    rt_rd_t nh_rdidx;
    rt_cnt_idx_t cntidx;
} rt_lpm_t;

#define RT_LPM_F_LOCAL          (1 <<  8)
#define RT_LPM_F_HAS_NEXTHOP    (1 <<  9)
#define RT_LPM_F_HAS_PORTINFO   (1 << 10)
#define RT_LPM_F_SUBNET         (1 << 11)

/**********************************************************************/
/* Address Resolution Table */

typedef struct rt_ipv4_ar_s {
    struct rt_ipv4_ar_s *prev, *next;
    /* Key */
    rt_port_info_t *pi;
    rt_ipv4_addr_t ipaddr;
    /* Result */
    uint32_t flags;
    rt_eth_addr_t hwaddr; /* Remote MAC address */
    rt_pkt_t pkt;
} rt_ipv4_ar_t;

#define RT_IPV4_AR_TABLE_SIZE 8192

#define RT_AR_F_HAS_HWADDR      (1 << 0)
#define RT_AR_F_HAS_PKT         (1 << 1)

/**********************************************************************/
/* Local Address Resolution database */

typedef struct rt_lat_s {
    struct rt_lat_s *prev, *next;
    /* Key */
    rt_port_info_t *pi;
    rt_ipv4_addr_t ipaddr;
    /* Result */
    uint32_t flags;
    rt_eth_addr_t hwaddr; /* Local MAC address */
} rt_lat_t;

#define RT_LAR_F_USE_PORT_HWADDR (1 << 0)

#define RT_LAR_TABLE_SIZE 8192

/**********************************************************************/

#define RT_DT_SIZE 65536
extern rt_dt_route_t rt_dt_table[RT_DT_SIZE];

static inline uint32_t
rt_dt_hash (const rt_dt_key_t *key)
{
    uint16_t idx = key->prtidx 
        + ((const uint16_t *) key)[0]
        + ((const uint16_t *) key)[1]
        + ((const uint16_t *) key)[5];

    return (uint32_t) idx;
}

#define rt_dt_key_compare(key1,key2) \
    (memcmp((key1), (key2), sizeof(rt_dt_key_t)) == 0)

static inline rt_dt_route_t *
rt_dt_lookup (const rt_dt_key_t *key)
{
    uint32_t idx = rt_dt_hash(key);
    rt_dt_route_t *hd = &rt_dt_table[idx];

    if (likely(rt_dt_key_compare(key, &hd->key)))
        return hd;

    rt_dt_route_t *sp = hd->next;
    while (likely(sp != hd)) {
        if (rt_dt_key_compare(key, &hd->key))
            return sp;
        sp = sp->next;
    }
    return NULL;
}

rt_dt_route_t *
    rt_dt_find_or_create (const rt_dt_key_t *key, const rt_dt_route_t *tp);
void rt_dt_set_fwd_info (rt_dt_route_t *dt, rt_lpm_t *rt, rt_ipv4_ar_t *ar,
    uint8_t flags);
rt_dt_route_t *rt_dt_create (const rt_dt_route_t *drp);
void rt_dt_init (void);
int rt_dt_sprintf (char *str, const rt_dt_route_t *dt);
void rt_dt_dump (FILE *fd);

/**********************************************************************/

rt_lpm_t *rt_lpm_lookup (rt_rd_t rdidx, rt_ipv4_addr_t addr);
rt_lpm_t *rt_lpm_lookup_subnet (rt_rd_t rdidx, rt_ipv4_addr_t addr);
rt_lpm_t *rt_lpm_find_or_create (rt_rd_t rdidx,
    rt_ipv4_prefix_t prefix, rt_port_info_t *pi);
rt_lpm_t *rt_lpm_route_create (rt_rd_t rdidx, rt_ipv4_addr_t ipaddr, int plen,
    uint32_t flags, rt_ipv4_addr_t nhipa, rt_rd_t nh_rdidx);
void rt_lpm_add_iface_addr (rt_port_info_t *pi,
    rt_ipv4_addr_t ipaddr, int plen);
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

extern void rt_lpm_table_init (void);
extern int rt_lpm_sprintf (char *str, const rt_lpm_t *rt);
extern void rt_lpm_dump (FILE *);
void rt_lpm_gen_icmp_requests (void);

/**********************************************************************/

void rt_ar_table_init (void);
rt_ipv4_ar_t *
rt_ipv4_ar_lookup (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr);
rt_ipv4_ar_t *rt_ipv4_ar_find_or_create (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr);
int rt_ipv4_ar_get_pkt (rt_pkt_t *pkt, rt_ipv4_ar_t *ar);
int rt_ipv4_ar_set_pkt (rt_pkt_t pkt, rt_ipv4_ar_t *ar);
rt_ipv4_ar_t *rt_ipv4_ar_learn (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr,
    rt_eth_addr_t hwaddr);

/**********************************************************************/

void rt_lat_init (void);
rt_lat_t *rt_lat_add (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr,
    rt_eth_addr_t *hwaddr);
rt_lat_t *rt_lat_db_lookup (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr);
rt_eth_addr_t *rt_lat_get_eth_addr (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr);

/**********************************************************************/

#endif
