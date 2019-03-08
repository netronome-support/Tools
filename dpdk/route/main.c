/*-
 *   BSD LICENSE
 *
 *   Copyright(c) 2010-2016 Intel Corporation. All rights reserved.
 *   All rights reserved.
 *
 *   Redistribution and use in source and binary forms, with or without
 *   modification, are permitted provided that the following conditions
 *   are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in
 *       the documentation and/or other materials provided with the
 *       distribution.
 *     * Neither the name of Intel Corporation nor the names of its
 *       contributors may be used to endorse or promote products derived
 *       from this software without specific prior written permission.
 *
 *   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 *   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 *   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 *   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 *   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 *   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 *   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 *   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 *   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 *   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include <sys/types.h>
#include <sys/queue.h>
#include <netinet/in.h>
#include <setjmp.h>
#include <stdarg.h>
#include <ctype.h>
#include <errno.h>
#include <getopt.h>
#include <signal.h>
#include <stdbool.h>

#include <rte_common.h>
#include <rte_log.h>
#include <rte_malloc.h>
#include <rte_memory.h>
#include <rte_memcpy.h>
#include <rte_memzone.h>
#include <rte_eal.h>
#include <rte_per_lcore.h>
#include <rte_launch.h>
#include <rte_atomic.h>
#include <rte_cycles.h>
#include <rte_prefetch.h>
#include <rte_lcore.h>
#include <rte_per_lcore.h>
#include <rte_branch_prediction.h>
#include <rte_interrupts.h>
#include <rte_pci.h>
#include <rte_random.h>
#include <rte_debug.h>
#include <rte_ether.h>
#include <rte_ethdev.h>
#include <rte_mempool.h>
#include <rte_mbuf.h>

#include "functions.h"
#include "pktutils.h"
#include "dbgmsg.h"
#include "rings.h"
#include "stats.h"
#include "port-process.h"

rt_global_t g;

static volatile bool force_quit;

#define RTE_LOGTYPE_ROUTE RTE_LOGTYPE_USER1

#define BURST_TX_DRAIN_US 100 /* TX drain every ~100us */
#define MEMPOOL_CACHE_SIZE 256

/*
 * Configurable number of RX/TX ring descriptors
 */
#define RTE_TEST_RX_DESC_DEFAULT 2048
#define RTE_TEST_TX_DESC_DEFAULT 2048
static uint16_t nb_rxd = RTE_TEST_RX_DESC_DEFAULT;
static uint16_t nb_txd = RTE_TEST_TX_DESC_DEFAULT;

#define RTE_MBUF_DESC_MARGIN    16384

/* ethernet addresses of ports */
static struct ether_addr rt_ports_eth_addr[RTE_MAX_ETHPORTS];

tx_ring_set_t *grs = NULL;

struct lcore_queue_conf {
    unsigned n_rx_port;
    unsigned rx_port_list[MAX_RX_QUEUE_PER_LCORE];
} __rte_cache_aligned;
struct lcore_queue_conf lcore_queue_conf[RTE_MAX_LCORE];

static struct rte_eth_dev_tx_buffer *tx_buffer[RTE_MAX_ETHPORTS];

struct rte_mempool * rt_pktmbuf_pool = NULL;

/* main processing loop */
static void
rt_main_loop (void)
{
    uint64_t prev_tsc, diff_tsc, cur_tsc, timer_tsc;
    const uint64_t drain_tsc = (rte_get_tsc_hz() + US_PER_S - 1) / US_PER_S *
            BURST_TX_DRAIN_US;

    prev_tsc = 0;
    timer_tsc = 0;

    rt_lcore_id_t lcore_id = rte_lcore_id();

    tx_queue_set_t *qs = create_queue_set(grs);
    tx_ring_set_t *trs = create_thread_ring_set(grs);
    rt_queue_list_t *rx_queue_list = create_thread_rx_queue_list(lcore_id);

    if ((rx_queue_list->count == 0)
            && (trs->count == 0)
            && (lcore_id != rte_get_master_lcore())) {
        RTE_LOG(INFO, ROUTE, "lcore %u has nothing to do\n", lcore_id);
        return;
    }

    RTE_LOG(INFO, ROUTE, "entering main loop on lcore %u\n", lcore_id);

    while (!force_quit) {

        cur_tsc = rte_rdtsc();

        /*
         * TX burst queue drain
         */
        diff_tsc = cur_tsc - prev_tsc;
        if (unlikely(diff_tsc > drain_tsc)) {

            /* if timer is enabled */
            if (g.timer_period > 0) {

                /* advance the timer */
                timer_tsc += diff_tsc;

                /* if timer has reached its timeout */
                if (unlikely(timer_tsc >= g.timer_period)) {

                    /* do this only on master core */
                    if (lcore_id == rte_get_master_lcore()) {
                        rt_dhcp_discover();

                        if (g.print_statistics) {
                            print_stats();
                        }
                        if (g.ping_nexthops) {
                            rt_lpm_gen_icmp_requests();
                        }

                        rt_port_periodic();

                        /* reset the timer */
                        timer_tsc = 0;
                    }
                }
            }

            prev_tsc = cur_tsc;
        }

        /*
         * Read packet from RX queues and process them
         */
        rx_port_process_task_list(rx_queue_list);

        tx_queue_flush_all(qs);

        flush_thread_ring_set(trs);
    }
}

static int
rt_launch_one_lcore (__attribute__((unused)) void *dummy)
{
    rt_main_loop();
    return 0;
}

/* Check the link status of all ports in up to 9s, and print them finally */
static void
check_all_ports_link_status (uint8_t port_num)
{
    #define CHECK_INTERVAL 100 /* 100ms */
    #define MAX_CHECK_TIME 90 /* 9s (90 * 100ms) in total */
    uint8_t portid, count, all_ports_up, print_flag = 0;
    struct rte_eth_link link;

    printf("\nChecking link status");
    fflush(stdout);
    for (count = 0; count <= MAX_CHECK_TIME; count++) {
        if (force_quit)
            return;
        all_ports_up = 1;
        for (portid = 0; portid < port_num; portid++) {
            if (force_quit)
                return;
            if (!port_enabled(portid))
                continue;
            memset(&link, 0, sizeof(link));
            rte_eth_link_get_nowait(portid, &link);
            /* print link status if flag set */
            if (print_flag == 1) {
                if (link.link_status)
                    printf("Port %d Link Up - speed %u "
                        "Mbps - %s\n", (uint8_t)portid,
                        (unsigned)link.link_speed,
                (link.link_duplex == ETH_LINK_FULL_DUPLEX) ?
                    ("full-duplex") : ("half-duplex\n"));
                else
                    printf("Port %d Link Down\n",
                        (uint8_t)portid);
                continue;
            }
            /* clear all_ports_up flag if any link down */
            if (link.link_status == ETH_LINK_DOWN) {
                all_ports_up = 0;
                break;
            }
        }
        /* after finally printing all link status, get out */
        if (print_flag == 1)
            break;

        if (all_ports_up == 0) {
            printf(".");
            fflush(stdout);
            rte_delay_ms(CHECK_INTERVAL);
        }

        /* set the print_flag if all ports up or timeout */
        if (all_ports_up == 1 || count == (MAX_CHECK_TIME - 1)) {
            print_flag = 1;
            printf("done\n");
        }
    }
}

static void
signal_handler (int signum)
{
    if (signum == SIGINT || signum == SIGTERM) {
        printf("\n\nSignal %d received, preparing to exit...\n", signum);
        force_quit = true;
    }
}

int
main (int argc, char **argv)
{
    struct rte_eth_dev_info dev_info;
    int ret;
    uint8_t nb_ports;
    uint8_t nb_ports_available;
    uint8_t portid;
    rt_lcore_id_t lcore_id;
    unsigned nb_ports_in_mask = 0;

    /* init EAL */
    ret = rte_eal_init(argc, argv);
    if (ret < 0)
        rte_exit(EXIT_FAILURE, "Invalid EAL arguments\n");
    argc -= ret;
    argv += ret;

    force_quit = false;
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    rt_global_init();
    rt_stats_init();
    dbgmsg_init();
    rt_lpm_table_init();
    rt_dt_init ();
    rt_port_table_init();
    rt_lat_init();
    rt_ar_table_init();

    /* parse application arguments (after the EAL ones) */
    ret = rt_parse_args(argc, argv);
    if (ret < 0)
        return -1;

    /* convert to number of cycles */
    g.timer_period *= rte_get_timer_hz();

    #if RTE_VERSION < RTE_VERSION_NUM(18,5,0,0)
    nb_ports = rte_eth_dev_count();
    #else
    nb_ports = rte_eth_dev_count_avail();
    #endif
    if (nb_ports == 0)
        rte_exit(EXIT_FAILURE, "No Ethernet ports - bye\n");

    /*
     * Each logical core is assigned a dedicated TX queue on each port.
     */
    for (portid = 0; portid < nb_ports; portid++) {
        /* skip ports that are not enabled */
        if (!port_enabled(portid))
            continue;

        nb_ports_in_mask++;

        rte_eth_dev_info_get(portid, &dev_info);
    }

    int nb_mbuf = nb_ports_in_mask * (nb_rxd + nb_txd)
        + RTE_MBUF_DESC_MARGIN;

    /* create the mbuf pool */
    rt_pktmbuf_pool = rte_pktmbuf_pool_create("mbuf_pool", nb_mbuf,
        MEMPOOL_CACHE_SIZE, 0, RTE_MBUF_DEFAULT_BUF_SIZE,
        rte_socket_id());
    if (rt_pktmbuf_pool == NULL)
        rte_exit(EXIT_FAILURE, "Cannot init mbuf pool\n");

    nb_ports_available = nb_ports;

    grs = create_global_ring_set(nb_ports);

    rt_lcore_default_assign(RT_PORT_DIR_RX, nb_ports);

    rt_lcore_default_assign(RT_PORT_DIR_TX, nb_ports);

    ret = rt_port_check_lcores();
    if (ret < 0)
        rte_exit(EXIT_FAILURE, "port-pinning is using unavailable lcores\n");

    log_port_lcore_assignment();

    /* Initialise each port */
    for (portid = 0; portid < nb_ports; portid++) {
        /* skip ports that are not enabled */
        if (!port_enabled(portid)) {
            printf("Skipping disabled port %u\n", (unsigned) portid);
            nb_ports_available--;
            continue;
        }
        /* init port */
        printf("Initializing port %u... ", (unsigned) portid);
        fflush(stdout);
        struct rte_eth_conf port_conf;
        memset(&port_conf, 0, sizeof(port_conf));

        ret = rte_eth_dev_configure(portid,
             /* nb_rx_queue = */ 1,
             /* nb_tx_queue = */ 1,
             &port_conf);
        if (ret < 0)
            rte_exit(EXIT_FAILURE, "Cannot configure device: err=%d, port=%u\n",
                  ret, (unsigned) portid);

        rte_eth_macaddr_get(portid, &rt_ports_eth_addr[portid]);

        /* init one RX queue */
        fflush(stdout);
        ret = rte_eth_rx_queue_setup(portid, 0, nb_rxd,
            rte_eth_dev_socket_id(portid),
            NULL, rt_pktmbuf_pool);
        if (ret < 0)
            rte_exit(EXIT_FAILURE, "rte_eth_rx_queue_setup:err=%d, port=%u\n",
                ret, (unsigned) portid);

        /* init one TX queue on each port */
        fflush(stdout);
        ret = rte_eth_tx_queue_setup(portid, 0, nb_txd,
            rte_eth_dev_socket_id(portid), NULL);
        if (ret < 0)
            rte_exit(EXIT_FAILURE, "rte_eth_tx_queue_setup:err=%d, port=%u\n",
                ret, (unsigned) portid);

        /* Initialize TX buffers */
        tx_buffer[portid] = rte_zmalloc_socket("tx_buffer",
                RTE_ETH_TX_BUFFER_SIZE(MAX_PKT_BURST), 0,
                rte_eth_dev_socket_id(portid));
        if (tx_buffer[portid] == NULL)
            rte_exit(EXIT_FAILURE, "Cannot allocate buffer for tx on port %u\n",
                    (unsigned) portid);

        rte_eth_tx_buffer_init(tx_buffer[portid], MAX_PKT_BURST);

        ret = rte_eth_tx_buffer_set_err_callback(tx_buffer[portid],
            rte_eth_tx_buffer_count_callback,
            &port_statistics[portid].qfull);
        if (ret < 0)
            rte_exit(EXIT_FAILURE, "Cannot set error callback for "
                "tx buffer on port %u\n", (unsigned) portid);

        /* Start device */
        ret = rte_eth_dev_start(portid);
        if (ret < 0)
            rte_exit(EXIT_FAILURE, "rte_eth_dev_start:err=%d, port=%u\n",
                  ret, (unsigned) portid);

        printf("done: \n");

        rt_port_create(portid, rt_ports_eth_addr[portid].addr_bytes,
            tx_buffer[portid]);

        rte_eth_promiscuous_enable(portid);
    }

    if (!nb_ports_available) {
        rte_exit(EXIT_FAILURE,
            "All available ports are disabled. Please set portmask.\n");
    }

    check_all_ports_link_status(nb_ports);

    ret = 0;
    /* launch per-lcore init on every lcore */
    rte_eal_mp_remote_launch(rt_launch_one_lcore, NULL, CALL_MASTER);
    RTE_LCORE_FOREACH_SLAVE(lcore_id) {
        if (rte_eal_wait_lcore(lcore_id) < 0) {
            ret = -1;
            break;
        }
    }

    for (portid = 0; portid < nb_ports; portid++) {
        if (!port_enabled(portid))
            continue;
        printf("Closing port %d...", portid);
        rte_eth_dev_stop(portid);
        rte_eth_dev_close(portid);
        printf(" Done\n");
    }
    printf("Bye...\n");

    return ret;
}
