#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include <rte_common.h>
#include <rte_cycles.h>
#include <rte_ether.h>
#include <rte_ethdev.h>
#include <rte_malloc.h>

#include "defines.h"
#include "port.h"

extern struct rte_mempool * rt_pktmbuf_pool;

int
rt_port_setup (void)
{
    //rt_port_index_t prtidx;
    rt_queue_index_t qidx;
    int rc;
    struct rte_eth_dev_tx_buffer *tx_buffer;

    /* Initialise each port */
    //for (prtidx = 0 ; prtidx < RTE_MAX_ETHPORTS ; prtidx++) {
    FOREACH_PORT(prtidx) {
        rt_port_info_t *pi = rt_port_lookup(prtidx);

        /* init port */
        printf("Initializing port %u (RX#Q: %u, TX#Q: %u)\n",
            prtidx, pi->rx_q_count, pi->tx_q_count);
        fflush(stdout);

        struct rte_eth_conf port_conf;
        memset(&port_conf, 0, sizeof(port_conf));

        rc = rte_eth_dev_configure(prtidx,
            pi->rx_q_count, pi->tx_q_count,
            &port_conf);
        if (rc < 0) {
            rte_exit(EXIT_FAILURE,
                "Cannot configure device: rc=%d, port=%u\n",
                rc, prtidx);
        }

        rte_eth_macaddr_get(prtidx, (struct ether_addr *) pi->hwaddr);

        /* Init RX queue(s) */
        for (qidx = 0 ; qidx < pi->rx_q_count ; qidx++) {
            rc = rte_eth_rx_queue_setup(prtidx, qidx, pi->rx_desc_cnt,
                rte_eth_dev_socket_id(prtidx),
                NULL, rt_pktmbuf_pool);
            if (rc < 0) {
                rte_exit(EXIT_FAILURE,
                    "rte_eth_rx_queue_setup: rc=%d, port=%u\n",
                    rc, prtidx);
            }
        }

        /* Init TX queue(s) */
        for (qidx = 0 ; qidx < pi->tx_q_count ; qidx++) {
            rc = rte_eth_tx_queue_setup(prtidx, qidx, pi->tx_desc_cnt,
                rte_eth_dev_socket_id(prtidx), NULL);
            if (rc < 0) {
                rte_exit(EXIT_FAILURE,
                    "rte_eth_tx_queue_setup: rc=%d, port=%u\n",
                    rc, prtidx);
            }
        }

        /* Initialize TX buffers */
        tx_buffer = rte_zmalloc_socket("tx_buffer",
            RTE_ETH_TX_BUFFER_SIZE(MAX_PKT_BURST), 0,
            rte_eth_dev_socket_id(prtidx));
        if (tx_buffer == NULL) {
            rte_exit(EXIT_FAILURE,
                "Cannot allocate buffer for TX on port %u\n",
                prtidx);
        }
        pi->tx_buffer = tx_buffer;

        rte_eth_tx_buffer_init(tx_buffer, MAX_PKT_BURST);

        rc = rte_eth_tx_buffer_set_err_callback(tx_buffer,
            rte_eth_tx_buffer_count_callback,
            &port_statistics[prtidx].qfull);
        if (rc < 0) {
            rte_exit(EXIT_FAILURE,
                "Cannot set error callback for TX buffer on port %u\n",
                prtidx);
        }

        /* Start device */
        rc = rte_eth_dev_start(prtidx);
        if (rc < 0) {
            rte_exit(EXIT_FAILURE,
                "rte_eth_dev_start: rc=%d, port=%u\n",
                rc, prtidx);
        }

        pi->flags |= RT_PORT_F_EXIST;

        /* Dump Port Information to log file */
        rt_port_dump_info(prtidx);

        rte_eth_promiscuous_enable(prtidx);
    }
    return 0;
}

int rt_port_desc_count (void)
{
    int count = 0;

    /* Initialise each port */
    FOREACH_PORT(prtidx) {
        rt_port_info_t *pi = rt_port_lookup(prtidx);
        if (pi->flags & RT_PORT_F_EXIST) {
            count += pi->rx_desc_cnt + pi->tx_desc_cnt;
        }
    }

    return count;
}

/* Check the link status of all ports in up to 9s, and print them finally */
void
rt_check_all_ports_link_status (void)
{
    #define CHECK_INTERVAL 100 /* 100ms */
    #define MAX_CHECK_TIME 90 /* 9s (90 * 100ms) in total */
    uint8_t count, all_ports_up, print_flag = 0;
    struct rte_eth_link link;

    printf("\nChecking link status");
    fflush(stdout);
    for (count = 0 ; count < MAX_CHECK_TIME ; count++) {
        if (g.force_quit)
            return;
        all_ports_up = 1;
        FOREACH_PORT(prtidx) {
            if (g.force_quit)
                return;
            memset(&link, 0, sizeof(link));
            rte_eth_link_get_nowait(prtidx, &link);
            /* print link status if flag set */
            if (print_flag == 1) {
                if (link.link_status)
                    printf("Port %d Link Up - speed %u "
                        "Mbps - %s\n", (uint8_t)prtidx,
                        (unsigned)link.link_speed,
                (link.link_duplex == ETH_LINK_FULL_DUPLEX) ?
                    ("full-duplex") : ("half-duplex\n"));
                else
                    printf("Port %d Link Down\n",
                        (uint8_t)prtidx);
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
