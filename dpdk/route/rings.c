#include "rings.h"
#include "dbgmsg.h"

/**********************************************************************/
/*  Queue Set */

void
tx_queue_flush_all (tx_queue_set_t *qsp)
{
    int prtcnt = qsp->prtcnt;
    int prtidx;
    for (prtidx = 0 ; prtidx < prtcnt ; prtidx++) {
        int pktcnt = qsp->pktcnt[prtidx];
        if (pktcnt > 0) {
            tx_queue_flush(qsp, prtidx, pktcnt);
        }
    }
}

RTE_DEFINE_PER_LCORE(tx_queue_set_t *, _queue_set);

/*
 * With information from the global ring set, create a
 * thread-private queue-set. This queue-set has one simple
 * FIFO per output port and will get flushed at the end of
 * each main-loop iteration by tx_queue_flush_all().
 */
tx_queue_set_t *
create_queue_set (const tx_ring_set_t *grs)
{
    uint32_t prtcnt = grs->count;
    int bufcnt = prtcnt * TX_QUEUE_SIZE;
    size_t size = prtcnt * sizeof(tx_queue_set_t);
    tx_queue_set_t *qsp = (tx_queue_set_t *) malloc(size);
    assert(qsp != NULL);
    memset(qsp, 0, size);
    qsp->ring   = (struct rte_ring **) malloc(prtcnt * sizeof(void *));
    qsp->pktcnt = (uint8_t *) malloc(prtcnt * sizeof(uint8_t));
    qsp->mbufs  = (void *) malloc(bufcnt * sizeof(void *));
    assert(qsp->ring != NULL);
    assert(qsp->pktcnt != NULL);
    assert(qsp->mbufs != NULL);
    uint32_t prtidx;
    for (prtidx = 0 ; prtidx < prtcnt ; prtidx++) {
        qsp->pktcnt[prtidx] = 0;
        qsp->ring[prtidx] = grs->ri[prtidx].ring;
    }
    qsp->prtcnt = grs->count;

    /* Save queue-set pointer to thread-private variable */
    RTE_PER_LCORE(_queue_set) = qsp;

    return qsp;
}

/**********************************************************************/
/*  Ring Set */

/*
 * Create Ring Set data structure of specified size
 */
static tx_ring_set_t *
create_ring_set (int count)
{
    int size = sizeof(tx_ring_set_t)
        + count * sizeof(tx_ring_info_t);
    tx_ring_set_t *rs = (tx_ring_set_t *) malloc(size);
    assert(rs != NULL);
    memset(rs, 0, size);
    rs->count = count;
    return rs;
}

/*
 * Create Global Ring Set data structure. Used for creating
 * thread-private Ring Sets. Notice that the lcore assignment
 * is left untouched.
 */
tx_ring_set_t *
create_global_ring_set (int prtcnt)
{
    tx_ring_set_t *rs = create_ring_set(prtcnt);
    int prtidx;
    for (prtidx = 0 ; prtidx < prtcnt ; prtidx++) {
        tx_ring_info_t *ri = &rs->ri[prtidx];
        char name[32];
        sprintf(name, "tx_port_%u", prtidx);
        ri->ring = rte_ring_create(name, TX_RING_SIZE,
            SOCKET_ID_ANY, RING_F_SC_DEQ);
        ri->prtidx = prtidx;
    }
    return rs;
}

/*
 * Based on the Global Ring Set, create a thread-private Ring Set.
 */
tx_ring_set_t *
create_thread_ring_set (tx_ring_set_t *grs)
{
    uint16_t lcore = rte_lcore_id();
    int prtcnt = 0;
    int prtidx;
    int thridx = 0;
    /* Count the number of ports needed */
    for (prtidx = 0 ; prtidx < grs->count ; prtidx++) {
        rt_port_info_t *pi = rt_port_lookup(prtidx);
        if (pi->tx_lcore == lcore)
            prtcnt++;
    }
    tx_ring_set_t *trs = create_ring_set(prtcnt);
    for (prtidx = 0 ; prtidx < grs->count ; prtidx++) {
        rt_port_info_t *pi = rt_port_lookup(prtidx);
        if (pi->tx_lcore == lcore) {
            tx_ring_info_t *ri = &trs->ri[thridx++];
            ri->ring = grs->ri[prtidx].ring;
            ri->prtidx = grs->ri[prtidx].prtidx;
        }
    }
    return trs;
}

/*
 * For all rings in a thread's ring-set, send out all packets
 */
void
flush_thread_ring_set (tx_ring_set_t *trs)
{
    int cnt = trs->count;
    int idx;
    struct rte_mbuf *mbufs[TX_RING_SIZE];
    for (idx = 0 ; idx < cnt ; idx++) {
        tx_ring_info_t *ri = &trs->ri[idx];
        struct rte_ring *ring = ri->ring;
        if (rte_ring_empty(ring))
            continue;
        uint16_t pktcnt = rte_ring_mc_dequeue_burst(ring,
            (void **) mbufs, TX_RING_SIZE);
        uint16_t sndcnt = rte_eth_tx_burst(ri->prtidx, 0, mbufs, pktcnt);
        if (unlikely(sndcnt < pktcnt)) {
            pktmbuf_free_bulk(&mbufs[sndcnt], pktcnt - sndcnt);
        }
    }
}

/*
 * Find the tx_ring for a specific port index
 */
tx_ring_info_t *
ring_set_find_port (tx_ring_set_t *grs, int prtidx)
{
    int i;
    for (i = 0 ; i < grs->count ; i++) {
        if (grs->ri[i].prtidx == prtidx)
            return &grs->ri[i];
    }
    return NULL;
}

/**********************************************************************/
