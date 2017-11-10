#include <arpa/inet.h>
#include <string.h>
#include "defines.h"
#include "tables.h"
#include "port.h"
#include "dbgmsg.h"

rt_port_info_t rt_port_table[RT_PORT_MAX];

void
rt_port_create (rt_port_index_t port, void *hwaddr, void *tx_buffer)
{
    rt_port_info_t *pi = rt_port_lookup(port);
    assert(tx_buffer != NULL);
    pi->flags |= RT_PORT_F_EXIST;
    pi->idx = port;
    memcpy(&pi->hwaddr, hwaddr, 6);
    pi->tx_buffer = tx_buffer;
    dbgmsg(INFO, nopkt, "Port %d: %s", port, rt_hwaddr_str(hwaddr));
}

void
rt_port_set_routing_domain (rt_port_index_t port, rt_rd_t rdidx)
{
    rt_port_info_t *pi = rt_port_lookup(port);
    pi->rdidx = rdidx;
}

void
rt_port_set_ipv4_addr (rt_port_index_t port, rt_ipv4_addr_t ipaddr, int len)
{
    rt_port_info_t *pi = rt_port_lookup(port);
    pi->ipaddr = ipaddr;
    pi->prefix.addr = ipaddr;
    pi->prefix.len  = len;
    /* Create a subnet-route and a host route */
    rt_ipv4_prefix_t prefix;
    prefix.addr = ipaddr;
    prefix.len = len;
    pi->prefix = prefix;
    /* Add a route to the LPM for the subnet */
    rt_lpm_find_or_create(pi->rdidx, prefix, pi);
    /* Add a LOCAL route to the LPM for the IP address */
    rt_lpm_host_create(pi->rdidx, ipaddr, pi, RT_LPM_F_LOCAL);

    dbgmsg(CONF, nopkt, "Port %d IP address (%d): %s/%u",
        port, pi->rdidx, rt_ipaddr_nr_str(ipaddr), len);
}

void
rt_port_set_ip_addr (rt_port_index_t port, const char *str, int len)
{
    rt_ipv4_addr_t ipaddr;
    inet_pton(AF_INET, str, &ipaddr);
    rt_port_set_ipv4_addr(port, ntohl(ipaddr), len);
}

void
rt_port_assign_thread (int prtidx, int direction, int lcore)
{
    rt_port_info_t *pi = rt_port_lookup(prtidx);
    switch (direction) {
        case RT_PORT_DIR_RX: pi->rx_lcore = lcore; break;
        case RT_PORT_DIR_TX: pi->tx_lcore = lcore; break;
    }
}

static inline uint16_t
rt_port_query_lcore (int prtidx, int direction)
{
    rt_port_info_t *pi = rt_port_lookup(prtidx);
    switch (direction) {
        case RT_PORT_DIR_RX: return pi->rx_lcore;
        case RT_PORT_DIR_TX: return pi->tx_lcore;
    }
    return RT_PORT_LCORE_UNASSIGNED;
}

static inline int
find_next_lcore_index (uint8_t lcore_idx)
{
    for (;;) {
        if (lcore_idx >= RTE_MAX_LCORE)
            lcore_idx = 0;
        if (rte_lcore_is_enabled(lcore_idx))
            return lcore_idx;
        lcore_idx++;
    }
}

void
rt_lcore_default_assign (int direction, int nb_ports,
    uint32_t portmask)
{
    uint8_t lcore_next_idx = 0;
    int prtidx;
    for (prtidx = 0 ; prtidx < nb_ports ; prtidx++) {
        if ((portmask & (1 << prtidx)) == 0)
            continue;
        /* Skip if the port is already assigned */
        uint16_t c_lcore = rt_port_query_lcore(prtidx, direction);
        if (c_lcore != RT_PORT_LCORE_UNASSIGNED)
            continue;
        uint16_t n_lcore = find_next_lcore_index(lcore_next_idx);
        rt_port_assign_thread(prtidx, direction, n_lcore);
        lcore_next_idx = n_lcore + 1;
    }
}

rx_port_list_t *
create_thread_rx_port_list (void)
{
    uint16_t lcore = rte_lcore_id();
    int prtcnt = 0;
    int prtidx;
    /* Count the number of ports needed */
    for (prtidx = 0 ; prtidx < RT_PORT_MAX ; prtidx++) {
        rt_port_info_t *pi = rt_port_lookup(prtidx);
        if (pi->rx_lcore == lcore) {
            prtcnt++;
        }
    }
    size_t size = sizeof(rx_port_list_t)
        + prtcnt * sizeof(rt_port_index_t);
    rx_port_list_t *pl = (rx_port_list_t *) malloc(size);
    assert(pl != NULL);
    pl->count = prtcnt;
    int lstidx = 0;
    for (prtidx = 0 ; prtidx < RT_PORT_MAX ; prtidx++) {
        rt_port_info_t *pi = rt_port_lookup(prtidx);
        if (pi->rx_lcore == lcore) {
            pl->prtidx[lstidx++] = prtidx;
        }
    }
    return pl;
}

void
log_port_lcore_assignment (uint32_t portmask)
{
    rt_port_index_t prtidx;
    for (prtidx = 0 ; prtidx < RT_PORT_MAX ; prtidx++) {
        if ((portmask & (1 << prtidx)) == 0)
            continue;
        rt_port_info_t *pi = rt_port_lookup(prtidx);
        dbgmsg(CONF, nopkt, "Port %u lcore assignment: RX: %u, TX: %u",
            prtidx, pi->rx_lcore, pi->tx_lcore);
    }
}

void
rt_port_table_init (void)
{
    int prtidx;
    for (prtidx = 0 ; prtidx < RT_PORT_MAX ; prtidx++) {
        memset(&rt_port_table[prtidx], 0, sizeof(rt_port_info_t));
        rt_port_info_t *pi = rt_port_lookup(prtidx);
        pi->idx = prtidx;
        pi->rx_lcore = RT_PORT_LCORE_UNASSIGNED;
        pi->tx_lcore = RT_PORT_LCORE_UNASSIGNED;
    }
}
