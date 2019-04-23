#include <stdio.h>

#include <rte_cycles.h>
#include <rte_log.h>
#include <rte_debug.h>
#include <rte_lcore.h>
#include <rte_ether.h>
#include <rte_ethdev.h>
#include <rte_prefetch.h>
#include <rte_cycles.h>

#include "defines.h"
#include "functions.h"
#include "ratelimit.h"

#define RTE_LOGTYPE_PING_TEST RTE_LOGTYPE_USER1

void
main_loop (void)
{
    struct rte_mbuf *pktlist[MAX_PKT_BURST];

    port_index_t prtidx = g.prtidx;

    rate_limit_t rl;
    /* Start out slow (5 pps) */
    double start_rate = min(g.rate, 5.0);
    rate_limit_setup(&rl, start_rate, 1);

    uint64_t count = 0;

    uint64_t max_duration = (uint64_t) (((double) rte_get_tsc_hz()) * g.duration);
    uint64_t passed_tsc = 0;
    uint32_t tsc_last = rte_rdtsc();

    while (!g.force_quit) {

        uint32_t tsc_now = rte_rdtsc();
        uint32_t diff = tsc_now - tsc_last;
        passed_tsc += diff;
        tsc_last = tsc_now;
        if (likely(max_duration > 0) && unlikely(passed_tsc > max_duration)) {
            g.force_quit = 1;
        }

        int i, credits = rate_limit_get_credit(&rl);
        if (credits > 0) {
            rate_limit_update(&rl, credits);

            for (i = 0 ; i < credits ; i++) {
                icmp_gen_request(g.r_ipv4_addr);
                if (unlikely(count == 5)) {
                    /* Set the rate to specified rate */
                    rate_limit_setup(&rl, g.rate, 8.0);
                }
                if (unlikely(g.count > 0)) {
                    if (unlikely(count >= g.count)) {
                        g.force_quit = 1;
                    }
                }
                count++;
            }
        }

        /* Flush Packet buffer */
        port_info_t *pi = port_lookup(prtidx);
        rte_eth_tx_buffer_flush(prtidx, 0, pi->tx_buffer);

        /* Fetch Packet Burst from Port */
        int pktcnt = rte_eth_rx_burst(prtidx, 0,
            pktlist, MAX_PKT_BURST);

        uint32_t tsc = rte_rdtsc();

        /* Process Packets */
        int idx;
        for (idx = 0 ; idx < pktcnt ; idx++) {
            struct rte_mbuf *m = pktlist[idx];
            rte_prefetch0(rte_pktmbuf_mtod(m, void *));
            pkt_process(prtidx, m, tsc);
        }
    }
}
