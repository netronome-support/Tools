#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

#include <rte_cycles.h>

#include "defines.h"
#include "dbgmsg.h"
#include "pktutils.h"

FILE *log_fd = NULL;
pkt_t nopkt;

dbgmsg_globals_t dbgmsg_globals;

static float dbg_speed_factor = 0;

static inline int64_t
dbg_calc_new_credits (dbgmsg_state_t *dbgstate)
{
    uint64_t tsc_current = rte_rdtsc();
    int64_t last = rte_atomic64_read(&dbgstate->last);
    if (last == 0) {
        /* First-time use */
        rte_atomic64_set(&dbgstate->last, tsc_current);
        rte_atomic64_set(&dbgstate->credits, dbgstate->maxcredits);
        return 0;
    }
    int64_t elapsed = tsc_current - last;
    /* Return no credits if no time has elapsed */
    if (elapsed < 0)
        return 0;
    /* Move 'last' forward and return updated value */
    int64_t updated = rte_atomic64_add_return(&dbgstate->last, elapsed);
    if (updated != (last + elapsed)) {
        /* If somebody else updated 'last', undo the operation */
        rte_atomic64_sub(&dbgstate->last, elapsed);
        return 0;
    }

    return (int64_t) ((float) (elapsed * dbgstate->speed) * dbg_speed_factor);
}

static inline float
dbg_check_credits (dbgmsg_state_t *dbgstate)
{
    /* Calculate new credits from elapsed time */
    int64_t new_credits = dbg_calc_new_credits(dbgstate);

    int64_t credits = rte_atomic64_read(&dbgstate->credits) + new_credits;
    if (credits < DBG_CREDIT_UNIT) {
        /* There are not enough credits */
        if (new_credits > 0) {
            /* Add new credits to state */
            rte_atomic64_add(&dbgstate->credits, new_credits);
        }
        rte_atomic64_inc(&dbgstate->suppressed);
        return 0;
    }
    new_credits -= DBG_CREDIT_UNIT;
    credits -= DBG_CREDIT_UNIT;
    if (credits > dbgstate->maxcredits) {
        rte_atomic64_set(&dbgstate->credits, dbgstate->maxcredits);
    } else {
        rte_atomic64_add(&dbgstate->credits, new_credits);
    }
    return 1;
}

void f_dbgmsg (dbgmsg_state_t *dbgstate,
    int level, pkt_t pkt, const char *fmt, ...)
{
    const int max_pkt_size_log_len = 2048;
    char str[256 + 3 * max_pkt_size_log_len];
    int n = 0;

    if (log_fd == NULL)
        return;

    if (dbg_check_credits(dbgstate) == 0)
        return;

    const char *lvlstr;
    switch (level) {
        case DEBUG:  lvlstr = "D"; break;
        case INFO:   lvlstr = "I"; break;
        case WARN:   lvlstr = "W"; break;
        case CONF:   lvlstr = "C"; break;
        case ERROR:  lvlstr = "E"; break;
        default:     lvlstr = "?"; break;
    }
    n += sprintf(&str[n], "%s ", lvlstr);

    va_list ap;
    va_start(ap, fmt);
    int rc = vsnprintf(&str[n], 2048, fmt, ap);
    va_end(ap);
    n += min(2048, rc);

    n += sprintf(&str[n], "\n");

    if ((pkt.mbuf != NULL) && (dbgmsg_globals.log_packets)) {
        n += sprintf(&str[n], "-  %18p  ", pkt.mbuf);
        int i;
        uint8_t *ba = (uint8_t *) pkt.eth;
        int len = min(dbgmsg_globals.log_pkt_len, pkt_length(pkt));
        len = min(len, max_pkt_size_log_len);
        for (i = 0 ; i < len ; i++)
            n += sprintf(&str[n], " %02x", ba[i]);
        n += sprintf(&str[n], "\n");
    }

    fprintf(log_fd, "%s", str);
    fflush(log_fd);
}

void dbgmsg_hexdump (void *data, int len)
{
    int i;
    for (i = 0 ; i < len ; i++)
        printf(" %02x", ((uint8_t *) data)[i]);
    printf("\n");
}

void dbgmsg_init (void)
{
    nopkt.mbuf = NULL;
    dbg_speed_factor = (float) DBG_CREDIT_UNIT / (float) rte_get_tsc_hz();
    dbgmsg_globals.log_level = INFO;
    dbgmsg_globals.log_packets = 0;
    dbgmsg_globals.log_pkt_len = 14 + 20 + 8;
}

int dbgmsg_fopen (const char *fname)
{
    if (log_fd != NULL)
        fclose(log_fd);
    log_fd = fopen(fname, "a");
    if (log_fd == NULL) {
        fprintf(stderr, "ERROR: faild to open %s\n", fname);
        return -1;
    }
    fprintf(log_fd, "\n\n----------\n");
    fflush(log_fd);
    return 0;
}

void dbgmsg_close (void)
{
    fflush(log_fd);
    fclose(log_fd);
}
