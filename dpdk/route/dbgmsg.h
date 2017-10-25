#ifndef __RT_DBGMSG_H__
#define __RT_DBGMSG_H__

#include <arpa/inet.h>
#include <stdint.h>

#include "defines.h"
#include "pktutils.h"

typedef struct {
    int log_level;
    int log_packets;
} dbgmsg_globals_t;

extern dbgmsg_globals_t dbgmsg_globals;

typedef struct {
    uint64_t last;
    int suppressed;
    float credits;
    float speed;
} dbgmsg_state_t;

extern void f_dbgmsg (dbgmsg_state_t *,
    int level, rt_pkt_t pkt, const char *fmt, ...);

extern rt_pkt_t nopkt;

#define dbgmsg(level, pkt, fmt, ...) \
do { \
    static dbgmsg_state_t dbgstate = { 0, 0, 64.0, 1.0 }; \
    f_dbgmsg(&dbgstate, level, pkt, fmt, ##__VA_ARGS__); \
} while(0)

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
extern int dbgmsg_fopen (const char *fname);
extern void dbgmsg_close (void);

#define ERROR   1
#define CONF    2
#define WARN    3
#define INFO    4
#define DEBUG   5

#endif
