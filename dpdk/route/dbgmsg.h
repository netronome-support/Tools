#ifndef __RT_DBGMSG_H__
#define __RT_DBGMSG_H__

#include <arpa/inet.h>

#include "defines.h"
#include "pktutils.h"

extern void dbgmsg (int level, rt_pkt_t pkt, const char *fmt, ...);
extern rt_pkt_t nopkt;

static inline const char *
rt_ipaddr_str (char *str, rt_ipv4_addr_t ipaddr)
{
    rt_ipv4_addr_t n = htonl(ipaddr);
    inet_ntop(AF_INET, &n, str, INET_ADDRSTRLEN);
    return str;
}

static inline const char *
rt_ipaddr_nr_str (rt_ipv4_addr_t ipaddr)
{
    static char str[INET_ADDRSTRLEN];
    rt_ipv4_addr_t n = htonl(ipaddr);
    inet_ntop(AF_INET, &n, str, INET_ADDRSTRLEN);
    return str;
}

static inline const char *
rt_hwaddr_str (const rt_eth_addr_t hwaddr)
{
    static char str[32];
    const uint8_t *a = (const uint8_t *) hwaddr;
    sprintf(str, "%02x:%02x:%02x:%02x:%02x:%02x",
        a[0], a[1], a[2], a[3], a[4], a[5]);
    return str;
}

void dbgmsg_hexdump (void *data, int len);

extern void dbgmsg_init (void);
extern void dbgmsg_close (void);

#define INFO    1
#define WARN    2
#define ERROR   3

#endif
