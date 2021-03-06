#ifndef __RT_DBGMSG_H__
#define __RT_DBGMSG_H__

#include <arpa/inet.h>
#include <stdint.h>

#include <rte_atomic.h>

#include "defines.h"
#include "pktdefs.h"

typedef struct {
    int log_level;
    int log_packets;
    int log_pkt_len;
} dbgmsg_globals_t;

extern dbgmsg_globals_t dbgmsg_globals;

typedef struct {
    int64_t maxcredits;
    int64_t speed;
    rte_atomic64_t last;
    rte_atomic64_t credits;
    rte_atomic64_t suppressed;
} dbgmsg_state_t;

#define DBG_CREDIT_UNIT ((int64_t) (1000000000))

#define DBGMSG_INIT(maxcredits,speed) \
    { ((maxcredits) * DBG_CREDIT_UNIT), (speed), \
        RTE_ATOMIC64_INIT(0), \
        RTE_ATOMIC64_INIT(0), \
        RTE_ATOMIC64_INIT(0) \
    }

extern void f_dbgmsg (dbgmsg_state_t *,
    int level, rt_pkt_t pkt, const char *fmt, ...);

extern rt_pkt_t nopkt;

#define CHK_LOGLEVEL(level) ((level) <= dbgmsg_globals.log_level)

#define dbgmsg_rate(level, maxcredits, rate, pkt, fmt, ...) \
do { \
    static dbgmsg_state_t dbgstate = DBGMSG_INIT((maxcredits),(rate)); \
    if (CHK_LOGLEVEL(level)) { \
        f_dbgmsg(&dbgstate, level, pkt, fmt, ##__VA_ARGS__); \
    } \
} while(0)

#define dbgmsg(level, pkt, fmt, ...) \
    dbgmsg_rate(level, 64, 1, pkt, fmt, ##__VA_ARGS__);

static inline const char *
rt_integer_str (char *str, int value)
{
    sprintf(str, "%d", value);
    return str;
}

static inline const char *
rt_ipaddr_str (char *str, rt_ipv4_addr_t ipaddr)
{
    rt_ipv4_addr_t n = htonl(ipaddr);
    inet_ntop(AF_INET, &n, str, INET_ADDRSTRLEN);
    return str;
}

static inline const char *
rt_prefix_str (char *str, rt_ipv4_prefix_t prefix)
{
    rt_ipv4_addr_t n = htonl(prefix.addr);
    inet_ntop(AF_INET, &n, str, INET_ADDRSTRLEN);
    int sl = strlen(str);
    sprintf(&str[sl], "/%d", prefix.len);
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
rt_hwaddr_str (char *str, const rt_eth_addr_t hwaddr)
{
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
