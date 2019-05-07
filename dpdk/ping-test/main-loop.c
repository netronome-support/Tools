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
#include "dbgmsg.h"
#include "functions.h"
#include "ratelimit.h"

#define RTE_LOGTYPE_PING_TEST RTE_LOGTYPE_USER1

void
main_loop (void)
{
    struct rte_mbuf *pktlist[MAX_PKT_BURST];

    port_index_t prtidx = g.prtidx;

    rate_limit_t rl;
    /* Start out slow (10 pps) */
    double start_rate = min(g.rate, 10.0);
    rate_limit_setup(&rl, start_rate, 1);

    uint64_t max_duration = (uint64_t) (((double) rte_get_tsc_hz()) * g.duration);
    uint64_t passed_tsc = 0;
    uint32_t tsc_last = rte_rdtsc();
    uint64_t collect_time_limit;

    /* Start ICMP at a much lower rate */
    int slow_start = 1;
    /* At the end allow for the last packets to arrive */
    int collect = 0;

    while (!g.force_quit) {

        uint32_t tsc_now = rte_rdtsc();
        uint32_t diff = tsc_now - tsc_last;
        passed_tsc += diff;
        tsc_last = tsc_now;

        if (likely(max_duration > 0) && unlikely(passed_tsc > max_duration)) {
            if (collect == 0) {
                collect_time_limit = passed_tsc + 2 * rte_get_tsc_hz();
            }
            collect = 1;
        }

        int i, credits = rate_limit_get_credit(&rl);
        if (unlikely(credits > 0)) {

            if (unlikely(collect)) {
                credits = 0;
                if (unlikely(passed_tsc > collect_time_limit)) {
                    break;
                }
                if (unlikely(icmp_stats.rx_seq_num == icmp_stats.tx_seq_num)) {
                    uint64_t delay = passed_tsc + rte_get_tsc_hz() / 4;
                    collect_time_limit = min(collect_time_limit, delay);
                }
            } else {
                if (unlikely(g.count > 0) && (icmp_stats.tx_pkt_cnt + credits > g.count)) {
                    collect_time_limit = passed_tsc + 2 * rte_get_tsc_hz();
                    collect = 1;
                    credits = min(0, g.count - icmp_stats.tx_pkt_cnt);
                }

                rate_limit_update(&rl, credits);

                for (i = 0 ; i < credits ; i++) {
                    icmp_gen_request(g.r_ipv4_addr);
                }
            }

            if (unlikely(slow_start)) {
                if ((icmp_stats.rx_pkt_cnt >= 5) ||
                    (icmp_stats.tx_pkt_cnt >= 10)) {
                    if (icmp_stats.rx_pkt_cnt < 5) {
                        /* Poor or no response - Terminate test */
                        char ts[32];
                        fprintf(stderr,
                            "ERROR: %s response from target (%s)\n",
                            (icmp_stats.rx_pkt_cnt == 0) ? "no" : "poor",
                            ipaddr_str(ts, g.r_ipv4_addr));
                        break;
                    }
                    /* Set the rate to specified rate */
                    rate_limit_setup(&rl, g.rate, 8.0);
                    slow_start = 0;
                    g.measure_latency = true;
                }
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
