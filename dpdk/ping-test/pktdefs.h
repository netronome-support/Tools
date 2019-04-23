#ifndef __RT_PKTDEFS_H__
#define __RT_PKTDEFS_H__

#include <rte_ethdev.h>
#include <rte_mbuf.h>

#include "defines.h"
#include "port.h"

#define PTR(ptr, type, offset) \
  ((type *) &(((char *) (ptr))[offset]))

typedef struct {
    uint8_t dst[6];
    uint8_t src[6];
    uint16_t ethtype;
} __attribute__((packed)) eth_hdr_t;

typedef struct {
    uint8_t     vershlen;
    uint8_t     TOS;
    uint16_t    length;
    uint16_t    ident;
    uint16_t    fraginfo;
    uint8_t     TTL;
    uint8_t     protocol;
    uint16_t    chksum;
    uint32_t    ipsa;
    uint32_t    ipda;
} __attribute__((packed)) ipv4_hdr_t;

typedef struct {
    uint16_t    srcp;
    uint16_t    dstp;
    uint16_t    length;
    uint16_t    chksum;
} __attribute__((packed)) udp_hdr_t;

typedef struct {
    uint8_t     type;
    uint8_t     code;
    uint16_t    chksum;
    uint16_t    ident;
    uint16_t    seq;
} __attribute__((packed)) icmp_hdr_t;

typedef struct {
    struct rte_mbuf *mbuf;
    port_info_t *pi; /* Receive Port */
    uint32_t r_tsc;
    eth_hdr_t *eth;
    struct {
        void *l3;
    } pp;
} pkt_t;

#endif
