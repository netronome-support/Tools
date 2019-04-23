#include <arpa/inet.h>
#include <string.h>
#include "defines.h"
#include "port.h"
#include "dbgmsg.h"
#include "functions.h"

port_info_t port_table[MAX_PORT_COUNT];

void
port_assign_thread (int prtidx, int direction, lcore_id_t lcore)
{
    port_info_t *pi = port_lookup(prtidx);
    switch (direction) {
        case PORT_DIR_RX: pi->rx_lcore = lcore; break;
        case PORT_DIR_TX: pi->tx_lcore = lcore; break;
    }
}

static inline uint16_t
port_query_lcore (int prtidx, int direction)
{
    port_info_t *pi = port_lookup(prtidx);
    switch (direction) {
        case PORT_DIR_RX: return pi->rx_lcore;
        case PORT_DIR_TX: return pi->tx_lcore;
    }
    return PORT_LCORE_UNASSIGNED;
}

static inline lcore_id_t
find_next_lcore_index (lcore_id_t lcore_id)
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
lcore_default_assign (int direction)
{
    lcore_id_t lcore_next_idx = 0;
    FOREACH_PORT(prtidx) {
        /* Skip if the port is already assigned */
        lcore_id_t c_lcore = port_query_lcore(prtidx, direction);
        if (c_lcore != PORT_LCORE_UNASSIGNED)
            continue;
        lcore_id_t n_lcore = find_next_lcore_index(lcore_next_idx);
        port_assign_thread(prtidx, direction, n_lcore);
        lcore_next_idx = n_lcore + 1;
    }
}

void
port_table_init (void)
{
    int prtidx;
    for (prtidx = 0 ; prtidx < MAX_PORT_COUNT ; prtidx++) {
        memset(&port_table[prtidx], 0, sizeof(port_info_t));
        port_info_t *pi = port_lookup(prtidx);
        pi->idx = prtidx;
        pi->rx_desc_cnt = RTE_RX_DESC_DEFAULT;
        pi->tx_desc_cnt = RTE_TX_DESC_DEFAULT;
        pi->rx_q_count = 1;
        pi->tx_q_count = 1;
    }
}
