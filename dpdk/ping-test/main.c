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

#include <rte_version.h>
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

#include "defines.h"
#include "functions.h"
#include "dbgmsg.h"

global_t g;

#define RTE_LOGTYPE_ROUTE RTE_LOGTYPE_USER1

#define BURST_TX_DRAIN_US 100 /* TX drain every ~100us */
#define MEMPOOL_CACHE_SIZE 256

struct rte_mempool * pktmbuf_pool = NULL;

static int
launch_one_lcore (__attribute__((unused)) void *dummy)
{
    main_loop();
    return 0;
}

static void
signal_handler (int signum)
{
    if (signum == SIGINT || signum == SIGTERM) {
        printf("\n\nSignal %d received, preparing to exit...\n", signum);
        g.force_quit = true;
    }
}

int
main (int argc, char **argv)
{
    struct rte_eth_dev_info dev_info;
    int rc, lcore_rc;
    uint8_t nb_ports;
    lcore_id_t lcore_id;

    /* init EAL */
    rc = rte_eal_init(argc, argv);
    if (rc < 0)
        rte_exit(EXIT_FAILURE, "Invalid EAL arguments\n");
    argc -= rc;
    argv += rc;

    g.force_quit = false;
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    global_init();
    dbgmsg_init();
    port_table_init();

    /* parse application arguments (after the EAL ones) */
    rc = parse_args(argc, argv);
    if (rc < 0)
        return -1;

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
    FOREACH_PORT(prtidx) {
        rte_eth_dev_info_get(prtidx, &dev_info);
    }

    int mbuf_count = port_desc_count()
        + RTE_MBUF_DESC_MARGIN;

    /* create the mbuf pool */
    pktmbuf_pool = rte_pktmbuf_pool_create("mbuf_pool", mbuf_count,
        MEMPOOL_CACHE_SIZE, 0, RTE_MBUF_DEFAULT_BUF_SIZE,
        rte_socket_id());
    if (pktmbuf_pool == NULL)
        rte_exit(EXIT_FAILURE, "Cannot init mbuf pool\n");

    port_setup();

    check_all_ports_link_status();

    latency_setup();

    lcore_rc = 0;

    /* launch per-lcore init on every lcore */
    rte_eal_mp_remote_launch(launch_one_lcore, NULL, CALL_MASTER);

    RTE_LCORE_FOREACH_SLAVE(lcore_id) {
        if (rte_eal_wait_lcore(lcore_id) < 0) {
            lcore_rc = -1;
            break;
        }
    }

    FOREACH_PORT(prtidx) {
        printf("Closing port %d...", prtidx);
        rte_eth_dev_stop(prtidx);
        rte_eth_dev_close(prtidx);
        printf(" Done\n");
    }

    rc = latency_print();
    if (rc < 0)
        return rc;

    if (g.dump_fname != NULL) {
        latency_dump(g.dump_fname);
    }

    return lcore_rc;
}
