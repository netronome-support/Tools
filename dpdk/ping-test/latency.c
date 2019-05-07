#include <stdio.h>
#include <stdint.h>
#include <assert.h>

#include <rte_cycles.h>

#include "defines.h"
#include "functions.h"

static uint32_t *lap;
static uint64_t la_size = 0;
static uint64_t total = 0;
static uint64_t samples = 0;

void latency_setup (void)
{
    uint64_t count = max(g.count, (uint64_t) (g.duration * g.rate));
    la_size = max(10000, min(1000000, count));
    lap = (uint32_t * ) malloc(la_size * sizeof(uint32_t));
    assert(lap != NULL);
}

void latency_save (uint32_t tsc)
{
    if (likely(g.measure_latency)) {
        total += tsc;
        if (samples < la_size)
            lap[samples] = tsc;
        samples++;
    }
}

int latency_print (void)
{
    if (samples == 0) {
        printf("\nERROR: no samples available - PING likely failed\n");
        return -1;
    }
    double avg = (double) total / (double) samples;
    double T = 1.0 / (double) rte_get_tsc_hz();
    double latency = T * avg;
    printf("\nAverage Latency: %.3lf ms\n\n", latency * 1000.0);
    return 0;
}

int latency_dump (const char *fname)
{
    uint64_t i;
    double T = 1.0 / (double) rte_get_tsc_hz();
    uint64_t sc = min(la_size, samples);
    FILE *fd = fopen(fname, "w");
    assert(fd != NULL);
    for (i = 0 ; i < sc ; i++) {
        double latency = T * (double) lap[i];
        fprintf(fd, "%.2lf\n", 1e6 * latency);
    }
    fclose(fd);
    return 0;
}
