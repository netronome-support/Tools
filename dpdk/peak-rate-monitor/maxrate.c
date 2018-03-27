#include <stdio.h>
#include <string.h>
#include <assert.h>

#include <rte_cycles.h>

#include "maxrate.h"

/**********************************************************************/

static uint64_t bg_tick_limit = 0;

sample_wheel_t sw[SAMPLE_WHEEL_COUNT];

static inline sample_t *
get_sample (uint64_t idx, sample_wheel_t *wp)
{
    return &wp->s[idx & (SAMPLE_WHEEL_SIZE - 1)];
}

monitor_t mon[MAX_MONITOR_CNT];
int monitor_cnt = 0;

static void
add_monitor (int prtidx, double window, double dampening)
{
    assert (prtidx < SAMPLE_WHEEL_COUNT);
    assert (window > 0.0);
    assert (dampening <= 1.0);
    monitor_t *mp = &mon[monitor_cnt];
    memset(mp, 0, sizeof(*mp));
    mp->prtidx = prtidx;
    mp->window = window;
    mp->ticks = 1 + (uint64_t) ((double) rte_get_tsc_hz() * window);
    mp->dampening = dampening;
    printf("Create Monitor %u %f (%lu) %f\n",
        prtidx, window, mp->ticks, dampening);
    monitor_cnt++;
}

void
maxrate_add_monitor_args (const char *argstr)
{
    int prtidx;
    float window;
    float dampening;
    sscanf(argstr, "%u:%f:%f", &prtidx, &window, &dampening);
    add_monitor(prtidx, window / 1e3, dampening);
}

static void
add_monitor_sample (uint64_t tick, int ignore)
{
    int monidx;
    for (monidx = 0 ; monidx < monitor_cnt ; monidx++) {
        monitor_t *mp = &mon[monidx];
        sample_wheel_t *swp = &sw[mp->prtidx];
        uint64_t idx = swp->idx;
        uint64_t trail = mp->trail;
        uint64_t maxtick = tick - mp->ticks;
        /*
         * If the delta between 'idx' and 'trail' is more than the
         * size of the sample wheel, move the 'trail' index forward.
         */
        if ((idx - trail) > SAMPLE_WHEEL_SIZE) {
            trail = idx - SAMPLE_WHEEL_SIZE + 1;
            sample_t *sp = get_sample(trail, swp);
            if (sp->tick > maxtick) {
                mp->trail = trail;
                continue;
            }
        }
        while (( trail + 8 ) < idx ) {
            sample_t *sp = get_sample(trail + 1, swp);
            if (sp->tick > maxtick)
                break;
            trail++;
        }
        mp->trail = trail;
        /*
         * The ignore flag allows the collection of max-rates to be 
         * suspended. Usually due to a recent 'statistics print-out'.
         */
        if (ignore)
            continue;
        /*
         * Get the Current and Historic sample
         */
        sample_t *csp = get_sample(idx, swp);
        sample_t *hsp = get_sample(trail, swp);
        uint64_t delta = csp->tick - hsp->tick;
        rate_t rate;
        /* Rates are measured in pkt or oct per TSC tick */
        rate.pkt = (double) (csp->pkt - hsp->pkt) / (double) delta;
        rate.oct = (double) (csp->oct - hsp->oct) / (double) delta;
        if (rate.pkt > mp->maxrate.pkt) {
            mp->maxrate.pkt = rate.pkt;
            /*
             * Also collect information about how many DPDK-burst and
             * packets that were part of the measurement.
             */
            mp->pkt.bursts = idx - trail;
            mp->pkt.packets = csp->pkt - hsp->pkt;
        }
        if (rate.oct > mp->maxrate.oct) {
            mp->maxrate.oct = rate.oct;
            mp->oct.bursts = idx - trail;
            mp->oct.packets = csp->pkt - hsp->pkt;
       }
    }
}

void
maxrate_print_monitors (void)
{
    #define FORMAT "%4s %8s %10s %10s %10s %10s\n"
    printf(FORMAT, "Port", "Window", "PktRate", "BitRate",
        "Loops", "Packets");
    printf(FORMAT, "", "[ms]", "[Mpps]", "[Gbps]", "", "");
    int monidx;
    for (monidx = 0 ; monidx < monitor_cnt ; monidx++) {
        monitor_t *mp = &mon[monidx];
        printf("%4u %8.3f %10.3f %10.3f %10u %10u\n",
            mp->prtidx,
            mp->window * 1e3,
            mp->maxrate.pkt / 1e6     * (double) rte_get_tsc_hz(),
            mp->maxrate.oct / 1e9 * 8 * (double) rte_get_tsc_hz(),
            mp->pkt.bursts,
            mp->pkt.packets);
        mp->maxrate.pkt *= mp->dampening;
        mp->maxrate.oct *= mp->dampening;
    }
}

/**********************************************************************/

static void
maxrate_clear_sample_wheels (void)
{
    int prtidx;
    for (prtidx = 0 ; prtidx < SAMPLE_WHEEL_COUNT ; prtidx++) {
        sample_wheel_t *swp = &sw[prtidx];
        swp->idx = 0;
        swp->s[0].tick = 0;
        swp->max[0].pkt = 0.0;
        swp->max[0].oct = 0.0;
        swp->max[1].pkt = 0.0;
        swp->max[1].oct = 0.0;
    }
    bg_tick_limit = rte_get_tsc_hz() / 100;
}

static inline void
store_sample (sample_wheel_t *wp, uint64_t tick,
    uint64_t pkt, uint64_t oct)
{
    uint64_t idx = wp->idx;
    sample_t *lsp = get_sample(idx, wp);
    if (tick != lsp->tick) {
        lsp = get_sample(++wp->idx, wp);
        lsp->tick = tick;
    }
    lsp->pkt = pkt;
    lsp->oct = oct;
}

static inline int
calc_rate (uint64_t count, sample_wheel_t *wp, rate_t *rp)
{
    uint64_t idx = wp->idx;
    if (idx < count)
        return 0;
    sample_t *csp = get_sample(idx, wp);
    sample_t *hsp = get_sample(idx - count, wp);
    uint64_t ticks = csp->tick - hsp->tick;
    rp->pkt = (double) (csp->pkt - hsp->pkt) / (double) ticks;
    rp->oct = (double) (csp->oct - hsp->oct) / (double) ticks;
//    printf("pkt: %10.3f  %lu %lu %lu (%lu)\n", rp->pkt,
//        csp->pkt, hsp->pkt, csp->pkt - hsp->pkt, ticks);
    return 1;
}

static inline void
update_max_rate (uint64_t count, rate_t *mrp, sample_wheel_t *wp)
{
    rate_t rate;
    int rc = calc_rate(count, wp, &rate);
    if (rc) {
        if (rate.pkt > mrp->pkt) mrp->pkt = rate.pkt;
        if (rate.oct > mrp->oct) mrp->oct = rate.oct;
    }
}

void
maxrate_save_sample (int prtidx, uint64_t tick, uint64_t lbgt,
    uint64_t pkt, uint64_t oct)
{
    sample_wheel_t *wp = &sw[prtidx];
    store_sample(wp, tick, pkt, oct);
    int ignore = ((tick - lbgt) < bg_tick_limit);
    if (!ignore) {
        update_max_rate(SAMPLE_MAX_0_COUNT, &wp->max[0], wp);
        update_max_rate(SAMPLE_MAX_1_COUNT, &wp->max[1], wp);
    }
    add_monitor_sample(tick, ignore);
}

static inline void
print_rate (double hz, double pkt, double oct)
{
    printf("   %9.3f %10.3f ",
        pkt * hz / 1e3,
        oct * hz / 1e6 * 8);
}

void
maxrate_print_header (void)
{
    #define HDR_FMT "%-8s %-23s %-23s %-23s\n"
    printf(HDR_FMT,
        "Port", "Most recent", "Max(50)", "Max(200)");
    printf(HDR_FMT, "",
        "     Kpps       Mbps",
        "     Kpps       Mbps",
        "     Kpps       Mbps");
}

void
maxrate_print_rates (int prtidx)
{
    sample_wheel_t *wp = &sw[prtidx];
    double hz = (double) rte_get_tsc_hz();
    printf("%4u: ", prtidx);
    rate_t rate;
    int rc = calc_rate(1000, wp, &rate);
    if (rc) {
        print_rate(hz, rate.pkt, rate.oct);
    } else {
        print_rate(hz, 0.0, 0.0);
    }
    print_rate(hz, wp->max[0].pkt, wp->max[0].oct);
    print_rate(hz, wp->max[1].pkt, wp->max[1].oct);
    printf("\n");

    double damp = 0.99;
    wp->max[0].pkt *= damp;
    wp->max[0].oct *= damp;
    wp->max[1].pkt *= damp;
    wp->max[1].oct *= damp;
}

void
maxrate_init (void)
{
    maxrate_clear_sample_wheels();
}

