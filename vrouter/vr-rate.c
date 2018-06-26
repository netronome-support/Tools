#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <inttypes.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>
#include <assert.h>

#define F_LIST_COUNT        (1 << 0)
#define F_LIST_REF          (1 << 1)
#define F_LIST_DROP         (1 << 2)
#define F_LIST_ONCE         (1 << 3)
#define F_LIST_NOHEADER     (1 << 4)
#define F_LIST_NORM         (1 << 5)
#define F_LIST_TOTAL        (1 << 6)
#define F_LIST_PKTSIZE      (1 << 7)
#define F_LIST_RATIO        (1 << 8)

#define SAMPLE_COUNT  16

typedef struct {
  uint64_t pkt;
  uint64_t oct;
  uint64_t drop; /* Same as 'errors' */
} cntset_t;

typedef struct {
  struct timeval tv0, tv1;
  cntset_t r; /* Receive Counters */
  cntset_t t; /* Transmit Counters */
} sample_t;

#define IFD_F_PRESENT       (1 << 0)

typedef struct ifdata_s {
  struct ifdata_s *next, *prev;
  int flags;
  enum { HEAD, IFACE, TOTAL_RESET, TOTAL, SPACE } type;
  const char *vifname;
  const char *ifname;
  sample_t smpl[SAMPLE_COUNT];
  sample_t ref;
} ifdata_t;

static void
ifdata_list_print (const ifdata_t *iflist)
{
    const ifdata_t *p;
    for (p = iflist ; ; p = p->next) {
        printf("%016x: %016x %016x %s\n", p, p->next, p->prev, p->ifname);
        if (p->next == iflist)
            break;
    }
    fflush(stdout);
}

static ifdata_t *
ifdata_find (ifdata_t *iflist, const char *ifname)
{
    ifdata_t *p;
    for (p = iflist->next ; p != iflist ; p = p->next) {
        if (strcmp(p->ifname, ifname) == 0)
            return p;
    }
    return NULL;
}

static void
ifdata_reset_present_bit (ifdata_t *iflist)
{
    ifdata_t *p;
    for (p = iflist->next ; p != iflist ; p = p->next) {
        p->flags &= ~IFD_F_PRESENT;
    }
}

static void
ifdata_purge_non_present (ifdata_t *iflist)
{
    ifdata_t *p;
    for (p = iflist->next ; p != iflist ; p = p->next) {
        if (!(p->flags & IFD_F_PRESENT)) {
            ifdata_t *rp = p;
            p = p->prev;
            p->next = rp->next;
            rp->next->prev = p;
            free(rp);
        }
    }
}


static ifdata_t *
ifdata_add (ifdata_t *iflist, const char *ifname)
{
    ifdata_t *p = (ifdata_t *) malloc(sizeof(ifdata_t));
    assert(p != NULL);
    memset(p, 0, sizeof(ifdata_t));
    p->next = iflist;
    p->prev = iflist->prev;
    iflist->prev->next = p;
    iflist->prev = p;
    return p;
}

static inline void
cntset_aggregate (cntset_t *tp, const cntset_t *sp)
{
  tp->pkt  += sp->pkt;
  tp->oct  += sp->oct;
  tp->drop += sp->drop;
}

static void
sample_aggregate (sample_t *tp, const sample_t *sp)
{
  cntset_aggregate(&tp->r, &sp->r);
  cntset_aggregate(&tp->t, &sp->t);
  tp->tv0 = sp->tv0;
  tp->tv1 = sp->tv1;
}

int vr_sample (ifdata_t *iflist, int smpidx)
{
    struct timeval tv0, tv1;
    char fname[128], cmd[256];
    sprintf(fname, "/tmp/.vrouter-vif-list-%u.dump", getpid());
    sprintf(cmd, "vif --list > %s", fname);

    gettimeofday(&tv0, NULL);

    system(cmd);

    gettimeofday(&tv1, NULL);
 
    FILE *fd = fopen(fname, "r");
    if (fd == NULL)
        return -1;

    ifdata_t *ifdp = NULL;
    int rc, state = 0;
    char buf[1024], *str;
    int added = 0;
    while ((str = fgets(buf, 200, fd)) != NULL) {
        if (strncmp(str, "vif", 3) == 0) {
            state = 1;
            char vifname[256], type[32], ifname[256]; 
            rc = sscanf(str, "%s %s %s", vifname, type, ifname);
            if ((rc < 3) || (strcmp(type, "OS:") != 0)) {
                strcpy(ifname, vifname);
            }
            ifdp = ifdata_find(iflist, ifname);
            added = 0;
            if (ifdp == NULL) {
                ifdp = ifdata_add(iflist, ifname);
                ifdp->type = IFACE;
                ifdp->vifname = strdup(vifname);
                ifdp->ifname = strdup(ifname);
                added = 1;
            }
            ifdp->flags |= IFD_F_PRESENT;
            continue;
        }
        if (state == 0)
            continue;
        state++;
        if (strstr(str, "X packets") != NULL) {
            sample_t *sp = &ifdp->smpl[smpidx];
            cntset_t *csp;
            if (strstr(str, "RX") != NULL) {
                csp = &sp->r;
            } else {
                csp = &sp->t;
                sp->tv0 = tv0;
                sp->tv1 = tv1;
                if (added) {
                    ifdp->ref = *sp;
                }
            }
            char tmp[256];
            rc = sscanf(str, "%s packets:%" SCNu64
                " bytes:%" SCNu64 " errors:%" SCNu64,
                tmp, &csp->pkt, &csp->oct, &csp->drop);
            continue;
        }
        if (strlen(str) == 0) {
            ifdp = NULL;
            state = 0;
        }
    }
    fclose(fd);
}

static inline int printField (int mode, int flags, char *str,
    const cntset_t *cp0, const cntset_t *cp1,
    float f, const cntset_t ref)
{
    // printf(":: cp0 %12llu  cp1 %12llu  ref %12llu\n", cp0->pkt, cp1->pkt, ref.pkt);

    int n = sprintf(str, "%10.3f  %11.3f",
        f * ((float) (cp1->pkt - cp0->pkt)) / 1e3,
        f * (float) (cp1->oct - cp0->oct) * 8.0 / 1e6);
    if (flags & F_LIST_NORM) {
        long int oct = (cp1->oct - cp0->oct)
                + 20 * (cp1->pkt - cp0->pkt); // Should this be '24'?
        n += sprintf(&str[n], "  %6.2f",
            f * (float) oct * 8.0 / 10e6 / 100.0);
    }
    if (flags & F_LIST_PKTSIZE) {
        int pktdiff = cp1->pkt - cp0->pkt;
        unsigned int aps = (pktdiff == 0) ? 0
            : ((cp1->oct - cp0->oct) / pktdiff);
        char buf[32] = "";
        if (pktdiff > 0)
            sprintf(buf, "%u", aps);
        else if (flags & F_LIST_ONCE)
            strcpy(buf, "-");
        n += sprintf(&str[n], "%8s", buf);
    }
    if (flags & F_LIST_COUNT) {
        uint64_t cnt = cp1->pkt - ((flags & F_LIST_REF) ? ref.pkt : 0);
        n += sprintf(&str[n], "  %12llu", cnt);
    }
    if (flags & F_LIST_DROP) {
        uint64_t cnt = cp1->drop - ((flags & F_LIST_REF) ? ref.drop : 0);
        n += sprintf(&str[n], "  %12llu", cnt);
    }
    return n;
}

static inline int printRatio (const sample_t *sp0, const sample_t *sp1, char *str)
{
    uint64_t r_diff_pkt_cnt = sp1->r.pkt - sp0->r.pkt;
    uint64_t t_diff_pkt_cnt = sp1->t.pkt - sp0->t.pkt;
    if ((r_diff_pkt_cnt == 0) || (t_diff_pkt_cnt == 0))
        return sprintf(str, "        ");
    double ratio = (double) t_diff_pkt_cnt / (double) r_diff_pkt_cnt;
   // return sprintf(str, "%12llu %12llu ", r_diff_pkt_cnt, t_diff_pkt_cnt);
    return sprintf(str, "  %6.2f", ratio * 100.0);
}

void printDiff (char *str,
    const sample_t *sp0, const sample_t *sp1,
    const ifdata_t *ifp,
    int flags)
{
    uint32_t usec =
        (sp1->tv0.tv_sec - sp0->tv0.tv_sec) * 1000000 +
        (sp1->tv0.tv_usec - sp0->tv0.tv_usec);
    float f = 1e6 / ((float) usec);
    int n = 0;
    n += printField(0, flags, &str[n],
        &sp0->r, &sp1->r, f, ifp->ref.r);
    n += sprintf(&str[n], "    ");
    n += printField(0, flags, &str[n],
        &sp0->t, &sp1->t, f, ifp->ref.t);
    if (flags & F_LIST_RATIO) {
        n += printRatio(sp0, sp1, &str[n]);
    }
}

static ifdata_t *ifdata_alloc (int type, const char *ifname)
{
    ifdata_t *p = (ifdata_t *) malloc(sizeof(ifdata_t));
    memset(p, 0, sizeof(ifdata_t));
    p->type = type;
    switch (type) {
      case TOTAL:
      case TOTAL_RESET:
        p->ifname = "TOTAL";
        break;
      default:
        p->ifname = ifname;
        break;
    }
    return p;
}

int main (int argc, char *argv[]) {
    char str[512];
    int flags = 0;
    int ifcnt = 0;
    int argidx, x = 1, y = 0;
    int nl = 13;
    int ifidx;
    int ival = 500000;
    int hist = 5;
    ifdata_t *ifdata[512];
    char buf[65536];
    // Running total entry pointer
    ifdata_t *tp;

    ifdata_t ifhead;
    ifhead.type = HEAD;
    ifhead.next = ifhead.prev = &ifhead;

    // Default Total Entry
    ifdata[ifcnt++] = ifdata_alloc(TOTAL_RESET, NULL);

    for (argidx = 1 ; argidx < argc ; argidx++) {
        char *arg = argv[argidx];
        int argleft = argc - argidx - 1;
        if ((strcmp(arg, "-h") == 0) || (strcmp(arg, "--help") == 0))
            goto Usage;
        if ((strcmp(arg, "-i") == 0) || (strcmp(arg, "--interval") == 0)) {
            if (argleft < 1) goto Usage;
            ival = (int) (1e6 * atof(argv[++argidx]));
        } else if (strcmp(arg, "--hist") == 0) {
            if (argleft < 1) goto Usage;
            hist = (int) (1e6 * atof(argv[++argidx]));
        } else if (strcmp(arg, "--long") == 0)
            flags |= F_LIST_COUNT;
        else if (strcmp(arg, "--count") == 0)
            flags |= F_LIST_COUNT;
        else if (strcmp(arg, "--list-drop") == 0)
            flags |= F_LIST_DROP;
        else if (strcmp(arg, "--reset") == 0)
            flags |= F_LIST_REF;
        else if (strcmp(arg, "--total-start") == 0)
            ifdata[ifcnt++] = ifdata_alloc(TOTAL_RESET, NULL);
        else if (strcmp(arg, "--space") == 0)
            ifdata[ifcnt++] = ifdata_alloc(SPACE, NULL);
        else if (strcmp(arg, "--total") == 0)
            ifdata[ifcnt++] = ifdata_alloc(TOTAL, NULL);
        else if (strcmp(arg, "--once") == 0)
            flags |= F_LIST_ONCE;
        else if (strcmp(arg, "--no-header") == 0)
            flags |= F_LIST_NOHEADER;
        else if (strcmp(arg, "--norm") == 0)
            flags |= F_LIST_NORM;
        else if (strcmp(arg, "--pktsize") == 0)
            flags |= F_LIST_PKTSIZE;
        else if (strcmp(arg, "--ratio") == 0)
            flags |= F_LIST_RATIO;
        else if (strcmp(arg, "-n") == 0)
            nl = 10;
        else {
            fprintf(stderr, "ERROR: unknown argument '%s'\n", arg);
            goto Usage;
        }
    }
    if (ifcnt == 0) {
      Usage:
        printf("%s [options]\n", argv[0]);
        printf(
          "  --once         - Run once and exit\n"
          "  --count        - Show packet counters\n"
          "  --list-drop    - List drop counters\n"
          "  --interval     - Measurement interval\n"
          "  --no-header    - Skip printing the header\n"
          "  --reset        - Adjust counters to start at zero\n"
          "  --pktsize      - Show Average Packet Size (APS)\n"
          "  --ratio        - Show ratio between receive and transmit\n"
          "  --norm         - Show column (GE) with normalized bit-rate\n"
          "                   (frame size incl. Ethernet inter-frame gap\n"
          );
        return 0;
    }

    vr_sample(&ifhead, 0);

    ifdata_t *p;
    for (p = ifhead.next ; p != &ifhead ; p = p->next) {
        p->ref = p->smpl[0];
    }

    for (;;) {
        usleep(ival);

        ifdata_reset_present_bit(&ifhead);

        vr_sample(&ifhead, x);

        ifdata_purge_non_present(&ifhead);

        int w = 23;
        int n = 0;
        char head[256] = "";
        strcat(head, "      Kpps");
        strcat(head, "         Mbps");
        if (flags & F_LIST_NORM) {
            // 100.0
            strcat(head, "      GE");
            w += 8;
        }
        if (flags & F_LIST_PKTSIZE) {
            strcat(head, "     APS");
            w += 8;
        }
        if (flags & F_LIST_COUNT) {
            strcat(head, "           cnt");
            w += 14;
        }
        if (flags & F_LIST_DROP) {
            strcat(head, "          drop");
            w += 14;
        }
        const char *fields = (flags & 1)
            ? "      Kpps         Mbps           cnt"
            : "      Kpps         Mbps";
        if (!(flags & F_LIST_NOHEADER)) {
            n += sprintf(&buf[n], "\n\n\n\n");
            n += sprintf(&buf[n], "%-*s  %-*s    %s\n",
                16, "Interface", w, "Receive", "Transmit");
            n += sprintf(&buf[n], "%-*s  %-*s    %s",
                16, "", w, head, head);
            if (flags & F_LIST_RATIO) {
                n += sprintf(&buf[n], "   ratio");
            }
            n += sprintf(&buf[n], "\n");
        }

        ifdata_t *p;
        for (p = ifhead.next ; p != &ifhead ; p = p->next) {
            if (p->type == IFACE) {
                printDiff(str, &p->smpl[y], &p->smpl[x], p, flags);
                n += sprintf(&buf[n], "%-16s  %s\n", p->ifname, str);
            }
        }

        printf("%s", buf);
        fflush(stdout);

        if (flags & F_LIST_ONCE)
            break;

        x = (x + 1) % 5;
        if (x == y)
            y = (y + 1) % 5;
    }

    return 0;
}
