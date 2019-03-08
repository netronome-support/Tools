#include <arpa/inet.h>
#include <string.h>
#include "defines.h"
#include "tables.h"
#include "port.h"
#include "dbgmsg.h"
#include "functions.h"

rt_port_info_t rt_port_table[RT_PORT_MAX];

void
rt_port_create (rt_port_index_t port, void *hwaddr, void *tx_buffer)
{
    rt_port_info_t *pi = rt_port_lookup(port);
    assert(tx_buffer != NULL);
    pi->flags |= RT_PORT_F_EXIST;
    pi->idx = port;
    /* Assign Port to default routing domain */
    pi->rdidx = RT_RD_DEFAULT;
    memcpy(&pi->hwaddr, hwaddr, 6);
    pi->tx_buffer = tx_buffer;
    char ts[32];
    dbgmsg(INFO, nopkt, "Port %d: %s", port, rt_hwaddr_str(ts, hwaddr));
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
    /* Add subnet to LPM table and Local Address Table */
    rt_lpm_add_iface_addr(pi, ipaddr, len);
}

void
rt_port_set_ip_addr (rt_port_index_t port, const char *str, int len)
{
    rt_ipv4_addr_t ipaddr;
    inet_pton(AF_INET, str, &ipaddr);
    rt_port_set_ipv4_addr(port, ntohl(ipaddr), len);
}

void
rt_port_assign_thread (int prtidx, int direction, rt_lcore_id_t lcore)
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

static inline rt_lcore_id_t
find_next_lcore_index (rt_lcore_id_t lcore_id)
{
    for (;;) {
        if (lcore_id >= RTE_MAX_LCORE)
            lcore_id = 0;
        if (rte_lcore_is_enabled(lcore_id))
            return lcore_id;
        lcore_id++;
    }
}

void
rt_lcore_default_assign (int direction, int nb_ports)
{
    rt_lcore_id_t lcore_next_idx = 0;
    int prtidx;
    for (prtidx = 0 ; prtidx <= nb_ports ; prtidx++) {
        if (!port_enabled(prtidx))
            continue;
        /* Skip if the port is already assigned */
        rt_lcore_id_t c_lcore = rt_port_query_lcore(prtidx, direction);
        if (c_lcore != RT_PORT_LCORE_UNASSIGNED)
            continue;
        rt_lcore_id_t n_lcore = find_next_lcore_index(lcore_next_idx);
        rt_port_assign_thread(prtidx, direction, n_lcore);
        lcore_next_idx = n_lcore + 1;
    }
}

rt_queue_list_t *
create_thread_rx_queue_list (rt_lcore_id_t lcore)
{
    int qcount = 0;
    int prtidx;
    /* Count the number of ports needed */
    for (prtidx = 0 ; prtidx < RT_PORT_MAX ; prtidx++) {
        rt_port_info_t *pi = rt_port_lookup(prtidx);
        if (pi->rx_lcore == lcore) {
            qcount++;
        }
    }
    size_t size = sizeof(rt_queue_list_t)
        + qcount * sizeof(rt_queue_t);
    rt_queue_list_t *qlist = (rt_queue_list_t *) malloc(size);
    assert(qlist != NULL);
    qlist->count = qcount;
    rt_queue_t *qp = &qlist->list[0];
    for (prtidx = 0 ; prtidx < RT_PORT_MAX ; prtidx++) {
        rt_port_info_t *pi = rt_port_lookup(prtidx);
        if (pi->rx_lcore == lcore) {
            qp->prtidx = prtidx;
            qp->queidx = 0; /* Only queue '0' for now */
            qp++;
        }
    }
    return qlist;
}

int
rt_port_check_lcores (void)
{
    rt_port_index_t prtidx;
    for (prtidx = 0 ; prtidx < RT_PORT_MAX ; prtidx++) {
        if (!port_enabled(prtidx))
            continue;
        int dir;
        for (dir = RT_PORT_DIR_RX ; dir <= RT_PORT_DIR_TX ; dir++) {
            rt_lcore_id_t lcore = rt_port_query_lcore(prtidx, dir);
            if (!rte_lcore_is_enabled(lcore)) {
                fprintf(stderr, "ERROR: lcore %u is not enabled\n", lcore);
                return -1;
            }
        }
    }
    return 0;
}

void
log_port_lcore_assignment (void)
{
    rt_port_index_t prtidx;
    for (prtidx = 0 ; prtidx < RT_PORT_MAX ; prtidx++) {
        if (!port_enabled(prtidx))
            continue;
        rt_port_info_t *pi = rt_port_lookup(prtidx);
        dbgmsg(CONF, nopkt, "Port %u lcore assignment: RX: %u, TX: %u",
            prtidx, pi->rx_lcore, pi->tx_lcore);
    }
}

void
rt_port_periodic (void)
{
    rt_port_index_t prtidx;
    for (prtidx = 0 ; prtidx < RT_PORT_MAX ; prtidx++) {
        rt_port_info_t *pi = rt_port_lookup(prtidx);
        if (pi->flags & RT_PORT_F_EXIST) {
            if (pi->flags & RT_PORT_F_GRATARP) {
                rt_arp_send_gratuitous(pi);
            }
        }
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
        pi->rdidx = RT_RD_DEFAULT;
        pi->rx_lcore = RT_PORT_LCORE_UNASSIGNED;
        pi->tx_lcore = RT_PORT_LCORE_UNASSIGNED;
    }
}
