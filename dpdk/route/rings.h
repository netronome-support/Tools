#ifndef __RT_RINGS_H__
#define __RT_RINGS_H__

#include <stdint.h>
#include <assert.h>

#include <rte_common.h>
#include <rte_mbuf.h>
#include <rte_ring.h>
#include <rte_ethdev.h>
#include <rte_lcore.h>

#include "defines.h"

/**********************************************************************/
#define TX_QUEUE_SIZE_SHIFT  (4)
#define TX_QUEUE_SIZE (1 << TX_QUEUE_SIZE_SHIFT)

typedef struct {
    uint16_t prtcnt;
    uint8_t size;
    uint8_t *pktcnt;
    /* Array of ring pointers */
    struct rte_ring **ring;
    /* Array of arrays of mbuf pointers */
    struct rte_mbuf **mbufs;
} tx_queue_set_t;

RTE_DECLARE_PER_LCORE(tx_queue_set_t *, _queue_set);

/**********************************************************************/
#define TX_RING_SIZE 16

/*
 * Each thread has its own private tx_ring_set_t
 * Once every process cycle these are flushed.
 * There is also a global ring set.
 */
typedef struct {
    uint16_t prtidx;
    struct rte_ring *ring;
} tx_ring_info_t;

typedef struct {
    int count;
    tx_ring_info_t ri[];
} tx_ring_set_t;

/**********************************************************************/
/*  Queue Set */

static inline struct rte_mbuf **
tx_queue_port_mbuf (tx_queue_set_t *qp, int prtidx)
{
    return &qp->mbufs[prtidx << TX_QUEUE_SIZE_SHIFT];
}

static inline void
pktmbuf_free_bulk (struct rte_mbuf *list[], unsigned n)
{
    unsigned int i;
    for (i = 0 ; i < n ; i++) {
        rte_pktmbuf_free(list[i]);
    }
}

static inline void
tx_queue_flush (tx_queue_set_t *qp, int prtidx, int count)
{
    struct rte_ring *ring = qp->ring[prtidx];
    struct rte_mbuf **mbufs = tx_queue_port_mbuf(qp, prtidx);
    int enqcnt = rte_ring_enqueue_burst(ring, (void *) mbufs, count);
    if (unlikely(enqcnt < count)) {
        pktmbuf_free_bulk(&mbufs[enqcnt], count - enqcnt);
    }
    qp->pktcnt[prtidx] = 0;
}

/*
 * Enqueue packet to thread-private queue
 */
static inline void
tx_pkt_enqueue (int prtidx, struct rte_mbuf *mbuf)
{
    /* Enqueue in thread-private queue */
    tx_queue_set_t *qsp = RTE_PER_LCORE(_queue_set);
    assert(qsp != NULL);
    assert(prtidx < qsp->prtcnt);
    int pos = qsp->pktcnt[prtidx];
    int mbufidx = (prtidx << TX_QUEUE_SIZE_SHIFT) + pos;
    qsp->mbufs[mbufidx] = mbuf;
    if (pos == (TX_QUEUE_SIZE - 1)) {
        tx_queue_flush(qsp, prtidx, TX_QUEUE_SIZE);
    } else {
        qsp->pktcnt[prtidx] = pos + 1;
    }
}

/**********************************************************************/

tx_queue_set_t *create_queue_set (const tx_ring_set_t *grs);
void tx_queue_flush_all (tx_queue_set_t *qsp);

void flush_thread_ring_set (tx_ring_set_t *trs);

tx_ring_info_t *ring_set_find_port (tx_ring_set_t *grs, int prtidx);
void global_ring_set_thread_assign (tx_ring_set_t *grs,
    int prtidx, int lcore);
tx_ring_set_t *create_global_ring_set (int prtcnt);
tx_ring_set_t *create_thread_ring_set (tx_ring_set_t *grs);
void global_ring_default_assign (tx_ring_set_t *grs,
    int nb_ports, uint32_t portmask);

#endif
