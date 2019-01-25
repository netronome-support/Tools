#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/stat.h>

#define OPT_F_ONCE          (1 << 0)
#define OPT_F_SKIP_ZERO     (1 << 1)
#define OPT_F_ZERO_START    (1 << 2)

enum {
  DUMP_OVS_OFCTL_FLOWS,
  DUMP_OVS_DPCTL_FLOWS,
};

typedef struct cmdlist_s {
  const char *cmdpath;
  const char *optargs;
  const char *defbridge;
} cmdlist_t;

cmdlist_t cmdlist[] = {
  { "/usr/local/bin", "-O OpenFlow13", "br0" },
  { "/usr/bin", "", "br-int" },
  { NULL, NULL, NULL }
};

const char *
select_ovs_vsctl_cmd (int mode, const char *fname, const char **brname)
{
  cmdlist_t *cp;
  const char *cmd;
  char binname[256];
  switch (mode) {
    case DUMP_OVS_OFCTL_FLOWS: cmd = "ovs-ofctl"; break;
    case DUMP_OVS_DPCTL_FLOWS: cmd = "ovs-dpctl"; break;
  }
  for (cp = &cmdlist[0] ; ; cp++) {
    if (cp->cmdpath == NULL) {
      fprintf(stderr, "ERROR: Could not find appropriate OVS command\n");
      return NULL;
    }
    struct stat fstat;
    sprintf(binname, "%s/%s", cp->cmdpath, cmd);
    int rc = lstat(binname, &fstat);
    if (rc < 0)
      continue;
    if (S_ISREG(fstat.st_mode))
      break;
  }
  if (*brname == NULL)
    *brname = cp->defbridge;
  static char syscmd[1024];
  switch (mode) {
    case DUMP_OVS_OFCTL_FLOWS:
      sprintf(syscmd, "%s %s dump-flows %s > %s",
        binname, cp->optargs, *brname, fname);
      break;
    case DUMP_OVS_DPCTL_FLOWS:
      sprintf(syscmd, "%s dump-flows > %s",
        binname, fname);
      break;
  }
  return syscmd;
}

int exec_ovs_dump_flows (const char *syscmd)
{
  return system(syscmd);
}

#define SMPL_F_HAS_START     (1 << 0)

typedef struct of_sample_s {
  struct of_sample_s *prev, *next;
  struct timeval tv;
  uint64_t pkt, oct;
  int table;
  int priority;
  int strnext;
  const char *brname;
  const char *filt;
  const char *action;
} of_sample_t;

void of_string_append (of_sample_t *sp,
  const char *str, int maxlen, const char **dpr)
{
  /* Get pointer to available string space */
  char *dp = &((char *) &sp[1])[sp->strnext];
  int len = strlen(str);
  if ((maxlen > 0) && (len > maxlen))
    len = maxlen;
  strncpy(dp, str, len);
  sp->strnext += 1 + len;
  /* Assign Destination Pointer Reference */
  if (dpr != NULL)
    *dpr = dp;
}

static inline int
same_rule (of_sample_t *s0, of_sample_t *s1)
{
  return (strcmp(s0->filt, s1->filt) == 0) &&
         (strcmp(s0->brname, s1->brname) == 0) &&
         (s0->priority == s1->priority) &&
         (s0->table == s1->table);
}

static of_sample_t *
find_matching_rule (of_sample_t *hp, of_sample_t *ep)
{
  of_sample_t *sp;
  for (sp = hp->next ; sp != hp ; sp = sp->next) {
    if (same_rule(sp, ep))
      return sp;
  }
  return NULL;
}

static void
free_list (of_sample_t *hp)
{
  while (hp->next != hp) {
    of_sample_t *fp = hp->next;
    hp->next = fp->next;
    free(fp);
  }
  hp->prev = hp;
  free(hp);
}

static inline int
ival_calc (struct timeval tv0, struct timeval tv1)
{
  return
    (tv1.tv_sec  - tv0.tv_sec) * 1000000 +
    (tv1.tv_usec - tv0.tv_usec);
}

static void
print_rule_stats (of_sample_t *hp0, of_sample_t *hp1, of_sample_t *hps,
  int flags)
{
  if (!(flags & OPT_F_ONCE))
    printf("\n\n\n\n\n\n\n\n");
  printf(
    "        [bytes]         [pkts]    [Mpps]  [Gbps]   "
    "Bridge  Tbl Pri  Action            Rule\n");

  double delta = ((double) ival_calc(hp1->tv, hp0->tv)) / 1e6;
  of_sample_t *ep0;
  for (ep0 = hp0->next ; ep0 != hp0 ; ep0 = ep0->next) {
    of_sample_t *ep1 = find_matching_rule(hp1, ep0);
    if (ep1 == NULL)
      continue;
    if ((flags & OPT_F_SKIP_ZERO) && (ep0->pkt == 0))
      continue;
    double pktrate = (double) (ep0->pkt - ep1->pkt) / 1e6 / delta;
    double bitrate = (double) (ep0->oct - ep1->oct) * 8.0 / 1e9 / delta;
    uint64_t pktcnt = ep0->pkt;
    uint64_t octcnt = ep0->oct;
    if (hps != NULL) {
      of_sample_t *eps = find_matching_rule(hps, ep0);
      if (eps != NULL) {
        pktcnt -= eps->pkt;
        octcnt -= eps->oct;
      }
    }
    printf("%15lu %14lu", octcnt, pktcnt);
    printf("   %7.3f %7.3f", pktrate, bitrate);
    printf("   %-7s %3u %3u  %-16s  %s\n",
      ep0->brname, ep0->table, ep0->priority, ep0->action, ep0->filt);
  }
  printf("\n");
}

static const char *
field_strip (char *str)
{
  char *eqp = strchr(str, '=');
  if (eqp == NULL) return "";
  *eqp = 0;
  str = &eqp[1];
  int sl = strlen(str);
  while ((sl > 0) && (str[sl - 1] == ','))
    str[--sl] = 0;
  return str;
}

static inline of_sample_t *sp_alloc(const char *line)
{
  int size = sizeof(of_sample_t) + 2 + strlen(line);
  of_sample_t *sp = (of_sample_t *) malloc(size);
  memset(sp, 0, size);
  return sp;
}

static of_sample_t *
read_stat_file (const char *brname, const char *fname,
  int mode, int flags)
{
  of_sample_t *hp = sp_alloc("");
  hp->next = hp->prev = hp;
  gettimeofday(&hp->tv, NULL);
  FILE *fd = fopen(fname, "r");
  char line[512];
  while (fgets(line, 512, fd) != NULL) {
    switch (mode) {
      case DUMP_OVS_OFCTL_FLOWS:
        if (strncmp(line, " cookie=", 8) != 0)
          continue;
        break;
    }
    /* Allocate data structure */
    of_sample_t *sp = sp_alloc(line);
    /* Set Bridge Name */
    of_string_append(sp, brname, 0, &sp->brname);
    /* Next Field pointer */
    const char *nfp = line;
    //printf("LINE:   %s", line);
    for (;;) {
      const char *str = nfp;
      //printf("NFP:    %s", nfp);
      char fns[512], as[512]; /* Field name string and argument string */
      while (isspace(*str))
        str++;
      if (*str == 0)
        break;
      const char *fnp = str;                    /* Field name pointer */
      const char *esp = index(str, '=');        /* Equal-sign pointer */
      const char *csp = index(str, ':');        /* Colon-sign pointer */
      const char *spp = index(str, ' ');        /* Space pointer */
      const char *asp;                          /* Argument field pointer */
      const char *efp;                          /* End-of-field pointer */
      if (spp != NULL) {
        /* Ignore colon and commas beyond a space */
        if ((esp != NULL) && (spp < esp)) esp = NULL;
        if ((csp != NULL) && (spp < csp)) csp = NULL;
        nfp = &spp[1];
      }
      if ((esp == NULL) && (csp == NULL))
        continue;
      else if (esp == NULL)
        asp = &csp[1];
      else if (csp == NULL)
        asp = &esp[1];
      else if (esp < csp)
        asp = &esp[1];
      else
        asp = &csp[1];
      nfp = asp;
      int fn_len = (int) (asp - fnp) - 1;
      strncpy(fns, fnp, fn_len);
      fns[fn_len] = 0;
      /* Search to the end of the 'field' */
      while (isgraph(*nfp))
        nfp++;
      /* Step back and eliminate potential commas */
      for (efp = nfp ; efp[-1] == ',' ; efp--)
        ;
      int as_len = (int) (efp - asp);
      const char *p;
      int i;
      /* Parse Argument String */
      for (i = 0, p = asp ; isgraph(*p) && (*p != ',') ; p++, i++)
        as[i] = *p;
      as[i] = 0;
      //printf("field: -%s-%s-\n", fns, as);
      /* Check for fields one-by-one */
      if (strcmp(fns, "cookie") == 0) {
        /* ignore */
      } else
      if (strcmp(fns, "duration") == 0) {
        /* ignore */
      } else
      if (strcmp(fns, "idle_age") == 0) {
        /* ignore */
      } else
      if (strcmp(fns, "n_packets") == 0) {
        sp->pkt   = strtoul(as, NULL, 0);
      } else
      if (strcmp(fns, "packets") == 0) {
        sp->pkt   = strtoul(as, NULL, 0);
      } else
      if (strcmp(fns, "n_bytes") == 0) {
        sp->oct   = strtoul(as, NULL, 0);
      } else
      if (strcmp(fns, "bytes") == 0) {
        sp->oct   = strtoul(as, NULL, 0);
      } else
      if (strcmp(fns, "table") == 0) {
        sp->table = strtoul(as, NULL, 0);
      } else
      if (strcmp(fns, "actions") == 0) {
        of_string_append(sp, asp, as_len, &sp->action);
      } else
      if (strcmp(fns, "priority") == 0) {
        sp->priority = strtoul(as, NULL, 0);
        /* This field is treated a little bit differently */
        const char *cfp = index(p, ',');
        if ((cfp == NULL) || (cfp > nfp)) {
          sp->filt = "";
        } else {
          of_string_append(sp, &cfp[1], (int) (efp - cfp), &sp->filt);
        }
      } else
      if (sp->filt == NULL) {
        of_string_append(sp, fnp, (int) (efp - fnp), &sp->filt);
      }
    }
    if ((sp->action == NULL) || (sp->filt == NULL)) {
      free(sp);
      printf("Could not parse: %s\n", line);
      continue;
    }
    // Link-in new entry
    sp->prev = hp->prev;
    sp->next = hp;
    hp->prev->next = sp;
    hp->prev = sp;
  }
  fclose(fd);
  return hp;
}

int main (int argc, char *argv[])
{
  of_sample_t *hp0 = NULL, *hp1 = NULL, *shp = NULL;

  int flags = 0;
  int mode = DUMP_OVS_OFCTL_FLOWS;
  const char *brname = NULL;
  double interval = 1.0;

  int ai;
  for (ai = 1 ; ai < argc ; ai++) {
    const char *arg = argv[ai];
    if (strcmp(arg, "--help") == 0) {
      printf("Usage: [--once] [--skip-zero] [--dp]"
        " [--int <seconds>] [<bridge name>]\n");
      return 0;
    }
    if (strcmp(arg, "--once") == 0) {
      flags |= OPT_F_ONCE;
      continue;
    }
    if (strcmp(arg, "--skip-zero") == 0) {
      flags |= OPT_F_SKIP_ZERO;
      continue;
    }
    if (strcmp(arg, "--dp") == 0) {
      mode = DUMP_OVS_DPCTL_FLOWS;
      continue;
    }
    if (strcmp(arg, "--int") == 0) {
      interval = atof(argv[++ai]);
      continue;
    }
    if (strcmp(arg, "--reset") == 0) {
      flags |= OPT_F_ZERO_START;
      continue;
    }
    brname = arg;
  }

  char fname[128];
  sprintf(fname, "/tmp/.ovs-dump-flows-%d.txt", getpid());

  const char *syscmd = select_ovs_vsctl_cmd(mode, fname, &brname);

  if (syscmd == NULL)
    return -1;

  int idx;
  for (idx = 0 ;; idx++) {

    exec_ovs_dump_flows(syscmd);

    hp0 = read_stat_file(brname, fname, mode, flags);

    if (hp1 != NULL) {
      print_rule_stats(hp0, hp1, shp, flags);
      if (flags & OPT_F_ONCE)
        break;
    }

    if ((shp == NULL) && (flags & OPT_F_ZERO_START))
      shp = hp0;

    if ((hp1 != NULL) && (hp1 != shp))
      free_list(hp1);

    // Rotate
    hp1 = hp0;
    hp0 = NULL;

    usleep(interval * 1e6);
  }
}
