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

    dbgmsg(INFO, nopkt, "Port %d IP address (%d): %s/%u",
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
rt_port_table_init (void)
{
    int i;
    for (i = 0 ; i < RT_PORT_MAX ; i++) {
        memset(&rt_port_table[i], 0, sizeof(rt_port_info_t));
    }
}
