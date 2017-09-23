#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

#include "defines.h"
#include "dbgmsg.h"

FILE *rt_log_fd = NULL;
rt_pkt_t nopkt;

void dbgmsg (int level, rt_pkt_t pkt, const char *fmt, ...)
{
    char str[4096];
    int n = 0;

    if (rt_log_fd == NULL)
        return;

    const char *lvlstr;
    switch (level) {
        case INFO:   lvlstr = "I"; break;
        case WARN:   lvlstr = "W"; break;
        case ERROR:  lvlstr = "E"; break;
        default:     lvlstr = "?"; break;
    }
    n += sprintf(&str[n], "%s ", lvlstr);

    if (pkt.pi != NULL)
        n += sprintf(&str[n], "%3u  ", pkt.pi->idx);
    else
        n += sprintf(&str[n], "     ");

    va_list ap;
    va_start(ap, fmt);
    int rc = vsnprintf(&str[n], 2048, fmt, ap);
    va_end(ap);
    n += min(2048, rc);

    n += sprintf(&str[n], "\n");

    if (pkt.mbuf != NULL) {
        n += sprintf(&str[n], "-  %18p  ", pkt.mbuf);
        int i;
        uint8_t *ba = (uint8_t *) pkt.eth;
        int len = min(14 + 20 + 8, rt_pkt_length(pkt));
        for (i = 0 ; i < len ; i++)
            n += sprintf(&str[n], " %02x", ba[i]);
        n += sprintf(&str[n], "\n");
    }

    fprintf(rt_log_fd, "%s", str);
    fflush(rt_log_fd);
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
    nopkt.pi = NULL;
}

int dbgmsg_fopen (const char *fname)
{
    if (rt_log_fd != NULL)
        fclose(rt_log_fd);
    rt_log_fd = fopen(fname, "a");
    if (rt_log_fd == NULL) {
        fprintf(stderr, "ERROR: faild to open %s\n", fname);
        return -1;
    }
    fprintf(rt_log_fd, "\n\n----------\n");
    fflush(rt_log_fd);
    return 0;
}

void dbgmsg_close (void)
{
    fflush(rt_log_fd);
    fclose(rt_log_fd);
}
