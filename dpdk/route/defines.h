#ifndef __RT_DEFINES_H__
#define __RT_DEFINES_H__

#include <assert.h>
#include <stdint.h>
#include <stddef.h>

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

#endif
