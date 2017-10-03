#include <stdlib.h>
#include <stdio.h>
#include <semaphore.h>

#include "tables.h"
#include "dbgmsg.h"
#include "functions.h"

/**********************************************************************/
/*  Direct Table (Must be FAST) */

rt_dt_route_t dt[RT_DT_SIZE];

static sem_t rt_dt_lock;

void rt_dt_create (rt_lpm_t *rt, rt_ipv4_addr_t ipaddr)
{
    assert(rt != NULL);
    rt_port_info_t *pi = rt->pi;
    assert(pi != NULL);
    rt_rd_t rdidx = pi->rdidx;
    assert(rt->pi->tx_buffer != NULL);

    uint32_t idx = rt_dt_hash(rdidx, ipaddr);
    rt_dt_route_t *hd = &dt[idx];
    rt_dt_route_t *np;

    /* Allocate a new entry just in case */
    rt_dt_route_t *ap = (rt_dt_route_t *) malloc(sizeof(rt_dt_route_t));
    assert(ap != NULL);

    sem_wait(&rt_dt_lock);
    if (hd->pi == NULL) {
        np = hd;
        /* Make sure no lookup matches (yet) */
        np->ipaddr = 0;
    } else {
        np = ap;
        ap = NULL; /* Mark allocated entry as used */
        /* Make sure no lookup matches (yet) */
        np->ipaddr = 0;
        /* Insert allocated entry into linked list */
        np->next = hd;
        np->prev = hd->prev;
        hd->prev->next = np;
        hd->prev = np;
    }
    /* Copy route information from LPM entry */
    np->rdidx   = rdidx;
    np->port    = pi->idx;
    np->tx_buffer = pi->tx_buffer;
    np->eth.dst = &rt->hwaddr;
    memcpy(&np->eth.src, &pi->hwaddr, 6);
    /* Copy the IP address last */
    np->ipaddr = ipaddr;

    sem_post(&rt_dt_lock);

    if (ap != NULL) {
        free(ap);
    }
}

void rt_dt_init (void)
{
    int i;
    for (i = 0 ; i < RT_DT_SIZE ; i++) {
        rt_dt_route_t *p = &dt[i];
        p->prev = p->next = p;
        p->rdidx = 0;
        p->ipaddr = 0;
    }
    int rc = sem_init(&rt_dt_lock, 1, 1);
    assert(rc == 0);
}

int
rt_dt_sprintf (char *str, const rt_dt_route_t *dt)
{
    int n = 0;
    char tmpstr[128];
    n += sprintf(&str[n], "(%u) %s - P: %u D: %s", dt->rdidx,
        rt_ipaddr_str(tmpstr, dt->ipaddr), dt->port,
        rt_hwaddr_str(*dt->eth.dst));
    n += sprintf(&str[n], " S: %s", rt_hwaddr_str(dt->eth.src));
    return n;
}

void
rt_dt_dump (FILE *fd)
{
    int i;
    for (i = 0 ; i < RT_DT_SIZE ; i++) {
        rt_dt_route_t *hd = &dt[i];
        rt_dt_route_t *p = hd;
        int i = 0;
        do {
            if (p->rdidx == 0)
                continue;
            char tmpstr[256];
            rt_dt_sprintf(tmpstr, p);
            fprintf(fd, " %s  %s\n", (i++ == 0) ? " " : "+", tmpstr);
        } while (p->next != hd);
    }
    fprintf(fd, "\n");
    fflush(fd);

}


/**********************************************************************/
/*  Route Table (LPM)  */

static rt_lpm_t rt_db_home;
static sem_t rt_lpm_lock;

rt_lpm_t *
rt_lpm_lookup (rt_rd_t rdidx, rt_ipv4_addr_t addr)
{
    rt_lpm_t *p;

    for (p = rt_db_home.prev ; p != &rt_db_home ; p = p->prev) {
        if (p->rdidx != rdidx)
            continue;
        uint32_t mask = 0xffffffff << (32 - p->prefix.len);
        if ( ( (addr ^ p->prefix.addr ) & mask ) == 0 ) {
            return p;
        }
    }
    return NULL;
}

rt_lpm_t *
rt_lpm_find_or_create (rt_rd_t rdidx, rt_ipv4_prefix_t prefix,
    rt_port_info_t *pi)
{
    rt_lpm_t *ne = (rt_lpm_t *) malloc(sizeof(rt_lpm_t));
    assert(ne != NULL);
    memset(ne, 0, sizeof(rt_lpm_t));
    ne->rdidx = rdidx;
    ne->prefix = prefix;
    if (pi != NULL) {
        ne->pi = pi;
        ne->flags |= RT_LPM_F_HAS_PORTINFO;
    }
    rt_lpm_t *p;
    sem_wait(&rt_lpm_lock);
    for (p = rt_db_home.next ;  ; p = p->next) {
        if ((p->rdidx == rdidx) && (p->prefix.addr == prefix.addr)
                && (p->prefix.len == prefix.len)) {
            p->pi = pi;
            p->flags |= RT_LPM_F_HAS_PORTINFO;
            free(ne);
            ne = p;
            break;
        }
        if ((p == &rt_db_home) || (prefix.len < p->prefix.len)) {
            ne->next = p;
            ne->prev = p->prev;
            p->prev->next = ne;
            p->prev = ne;
            break;
        }
    }
    sem_post(&rt_lpm_lock);
    return ne;
}

rt_lpm_t *
rt_lpm_route_create (rt_rd_t rdidx, rt_ipv4_addr_t ipaddr, int plen,
    rt_ipv4_addr_t nhipa)
{
    rt_ipv4_prefix_t prefix;
    prefix.addr = ipaddr;
    prefix.len = plen;
    rt_lpm_t *rt = rt_lpm_find_or_create(rdidx, prefix, NULL);
    assert(rt != NULL);
    rt->nhipa = nhipa;
    rt->flags |= RT_LPM_F_HAS_NEXTHOP;
    return rt;
}

void
rt_lpm_table_init (void)
{
    rt_db_home.prev = &rt_db_home;
    rt_db_home.next = &rt_db_home;
    int rc = sem_init(&rt_lpm_lock, 1, 1);
    assert(rc == 0);
}

int
rt_lpm_sprintf (char *str, const rt_lpm_t *rt)
{
    int n = 0;
    char tmpstr[128];
    uint32_t flags = rt->flags;
    n += sprintf(&str[n], "(%u) %s/%u", rt->rdidx,
        rt_ipaddr_str(tmpstr, rt->prefix.addr), rt->prefix.len);
    if (flags & RT_LPM_F_HAS_NEXTHOP) {
        n += sprintf(&str[n], " NH: %s",
            rt_ipaddr_str(tmpstr, rt->nhipa));
    }
    if (rt->nh) {
        rt_lpm_sprintf(tmpstr, rt->nh);
        n += sprintf(&str[n], " [%s]", tmpstr);
    }
    if (flags & RT_LPM_F_HAS_HWADDR) {
        n += sprintf(&str[n], " %s",
            rt_hwaddr_str(rt->hwaddr));
    }
    if (flags & RT_LPM_F_LOCAL) {
        n += sprintf(&str[n], " LOCAL");
    }
    if (flags & RT_LPM_F_HAS_PORTINFO) {
        n += sprintf(&str[n], " P%u", rt->pi->idx);
    }
    return n;
}

void
rt_lpm_dump (FILE *fd)
{
    rt_lpm_t *p;

    fprintf(fd, "H %18p %18p %18p\n",
        &rt_db_home, rt_db_home.prev, rt_db_home.next);
    fflush(fd);

    for (p = rt_db_home.next ; p != &rt_db_home ; p = p->next) {
        char tmpstr[256];
        rt_lpm_sprintf(tmpstr, p);
        fprintf(fd, "- %18p %18p %18p  %s\n", p, p->prev, p->next,
            tmpstr);
        fflush(fd);
    }
}

void
rt_lpm_gen_icmp_requests (void)
{
    dbgmsg(INFO, nopkt, "Periodic request to Generate ICMP PINGs");

    rt_lpm_t *p;

    for (p = rt_db_home.next ; p != &rt_db_home ; p = p->next) {
        if ((p->flags & RT_LPM_F_HAS_NEXTHOP) && (p->nh == NULL)) {
            p->nh = rt_resolve_nexthop(p->rdidx, p->nhipa);
        }
    }

    for (p = rt_db_home.next ; p != &rt_db_home ; p = p->next) {
        if (p->flags & RT_LPM_F_IS_NEXTHOP) {
            rt_icmp_gen_request(p->pi->rdidx, p->prefix.addr);
        }
    }
}

/**********************************************************************/

