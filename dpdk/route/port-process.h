#ifndef __RT_PORT_PROCESS_H__
#define __RT_PORT_PROCESS_H__

#include <rte_common.h>
#include <rte_mbuf.h>
#include <rte_prefetch.h>

#include "port.h"
#include "functions.h"

/*
 * Walk through a lcore-specific list of RX queues to poll packets from.
 */
static inline void
rx_port_process_task_list (const rt_queue_list_t *ql)
{
    struct rte_mbuf *pktlist[MAX_PKT_BURST];
    int idx;
    int count = ql->count;
    const rt_queue_t *qp;

    /* Walk through queues assigned to this 'lcore' */
    for (qp = &ql->list[0] ; count-- > 0 ; qp++) {
        rt_port_index_t prtidx = qp->prtidx;

        /* Fetch Packet Burst from Port */
        int pktcnt = rte_eth_rx_burst(prtidx, qp->queidx,
            pktlist, MAX_PKT_BURST);

        /* Update RX statistics */
        port_statistics[prtidx].rx += pktcnt;
        update_load_statistics(prtidx, pktcnt);

        /* Process Packets */
        for (idx = 0 ; idx < pktcnt ; idx++) {
            struct rte_mbuf *m = pktlist[idx];
            rte_prefetch0(rte_pktmbuf_mtod(m, void *));
            rt_pkt_process(prtidx, m);
        }
    }
}

#endif
