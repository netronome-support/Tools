#include <stdlib.h>
#include <stdio.h>
#include <semaphore.h>

#include "tables.h"
#include "dbgmsg.h"
#include "functions.h"

/**********************************************************************/
/*  Direct Table (Must be FAST) */

rt_dt_route_t rt_dt_table[RT_DT_SIZE];

static sem_t rt_dt_lock;

static void
rt_dt_copy_fwd_info (rt_dt_route_t *dp, const rt_dt_route_t *sp)
{
    if (dp->pi != sp->pi) {
        /* Temporarily set the entry to DISCARD */
        dp->flags = RT_FWD_F_DISCARD;
    }
    dp->tx_buffer = sp->tx_buffer;
    dp->pi = sp->pi;
    dp->port = sp->port;
    memcpy(dp->eth.dst, sp->eth.dst, 6);
    memcpy(dp->eth.src, sp->eth.src, 6);
    dp->flags = sp->flags;
}

rt_dt_route_t *
rt_dt_find_or_create (const rt_dt_key_t *key, const rt_dt_route_t *tp)
{
    /* Allocate new entry (just in case) */
    rt_dt_route_t *ap = (rt_dt_route_t *) malloc(sizeof(rt_dt_route_t));
    assert(ap != NULL);
    memset(ap, 0, sizeof(rt_dt_route_t));

    int idx = rt_dt_hash(key);
    rt_dt_route_t *hd = &rt_dt_table[idx];
    rt_dt_route_t *sp;

    sem_wait(&rt_dt_lock);
    for (sp = hd ; ; sp = sp->next) {
        if (rt_dt_key_compare(key, &sp->key))
            break;
        if (sp->next == hd) {
            if (hd->pi == NULL) {
                sp = hd;
            } else {
                /* Insert 'ap' at end of list */
                ap->next = hd;
                ap->prev = hd->prev;
                hd->prev->next = ap;
                hd->prev = ap;
                sp = ap;
                ap = NULL;
            }
            memcpy(&sp->key, key, sizeof(rt_dt_key_t));
            if (tp != NULL) {
                rt_dt_copy_fwd_info(sp, tp);
            } else {
                sp->flags = RT_FWD_F_DISCARD;
            }
            break;
        }
    }
    sem_post(&rt_dt_lock);

    /* If the ap was not used (ap != NULL), then relase it */
    free(ap);

    return sp;
}

void rt_dt_set_fwd_info (rt_dt_route_t *dt, rt_lpm_t *rt, rt_ipv4_ar_t *ar,
    uint8_t flags)
{
    assert(rt != NULL);
    rt_port_info_t *pi = rt->pi;
    assert(pi != NULL);
    assert(rt->pi->tx_buffer != NULL);

    sem_wait(&rt_dt_lock);

    dt->port = pi->idx;
    dt->tx_buffer = pi->tx_buffer;
    memcpy(&dt->eth.src, &pi->hwaddr, 6);
    if (ar != NULL) {
        memcpy(&dt->eth.dst, ar->hwaddr, 6);
    }

    /* Change Flags last */
    dt->flags = flags;

    sem_post(&rt_dt_lock);
}

rt_dt_route_t *
rt_dt_create (const rt_dt_route_t *drp)
{
    rt_dt_route_t *np = rt_dt_find_or_create(&drp->key, drp);
    assert(np != NULL);

    return np;
}

void
rt_dt_init (void)
{
    int i;
    for (i = 0 ; i < RT_DT_SIZE ; i++) {
        rt_dt_route_t *p = &rt_dt_table[i];
        memset(p, 0, sizeof(rt_dt_route_t));
        p->prev = p->next = p;
    }
    int rc = sem_init(&rt_dt_lock, 1, 1);
    assert(rc == 0);
}

int
rt_dt_sprintf (char *str, const rt_dt_route_t *dt)
{
    int n = 0;
    char ts1[32], ts2[32];
    n += sprintf(&str[n], "(%u) %s - P: %u D: %s", dt->key.prtidx,
        rt_ipaddr_str(ts1, dt->key.ipaddr), dt->port,
        rt_hwaddr_str(ts2, dt->eth.dst));
    n += sprintf(&str[n], " S: %s", rt_hwaddr_str(ts1, dt->eth.src));
    return n;
}

void
rt_dt_dump (FILE *fd)
{
    int i;
    for (i = 0 ; i < RT_DT_SIZE ; i++) {
        rt_dt_route_t *hd = &rt_dt_table[i];
        rt_dt_route_t *p = hd;
        int i = 0;
        do {
//            if (p->rdidx == 0)
//                continue;
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

static inline uint32_t
rt_ipv4_mask (int plen)
{
    return ((uint64_t) 0xffffffff) << (32 - plen);
}

rt_lpm_t *
rt_lpm_lookup (rt_rd_t rdidx, rt_ipv4_addr_t addr)
{
    rt_lpm_t *p;

    for (p = rt_db_home.prev ; p != &rt_db_home ; p = p->prev) {
        if (p->rdidx != rdidx)
            continue;
        if ( ( (addr ^ p->prefix.addr ) & rt_ipv4_mask(p->prefix.len) ) == 0 ) {
            return p;
        }
    }
    return NULL;
}

rt_lpm_t *
rt_lpm_lookup_subnet (rt_rd_t rdidx, rt_ipv4_addr_t addr)
{
    rt_lpm_t *p;

    for (p = rt_db_home.prev ; p != &rt_db_home ; p = p->prev) {
        if (p->rdidx != rdidx)
            continue;
        if ((p->flags & RT_LPM_F_SUBNET) == 0)
            continue;
        if ( ( (addr ^ p->prefix.addr ) & rt_ipv4_mask(p->prefix.len) ) == 0 ) {
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
    char ts0[64], ts1[32];
    dbgmsg(INFO, nopkt, "Adding LPM route for (%d) %s -> port %s",
        rdidx, rt_prefix_str(ts0, prefix),
        (pi != NULL) ? rt_integer_str(ts1, pi->idx) : "VOID");
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
    uint32_t flags, rt_ipv4_addr_t nhipa, rt_rd_t nh_rdidx)
{
    rt_ipv4_prefix_t prefix;
    prefix.addr = ipaddr;
    prefix.len = plen;
    rt_lpm_t *rt = rt_lpm_find_or_create(rdidx, prefix, NULL);
    assert(rt != NULL);
    rt->nhipa = nhipa;
    rt_lpm_t *srp = rt_lpm_lookup_subnet(rdidx, nhipa);
    if (srp == NULL) {
        char ts[32];
        fprintf(stderr, "ERROR: can not create route with NHIPA %s\n",
            rt_ipaddr_str(ts, nhipa));
        return NULL;
    }
    rt->pi = srp->pi;
    rt->nh_rdidx = nh_rdidx;
    rt->flags |= flags;
    return rt;
}

void
rt_lpm_add_iface_addr (rt_port_info_t *pi,
    rt_ipv4_addr_t ipaddr, int plen)
{
    char ipastr[32];
    rt_ipaddr_str(ipastr, ipaddr);
    if (plen == 32) {
        dbgmsg(CONF, nopkt, "Adding port %d address: %s",
            pi->idx, ipastr);
    } else {
        dbgmsg(CONF, nopkt, "Adding port %d subnet: %s/%u",
            pi->idx, ipastr, plen);
    }
    /* Add to Local Address Table (for ARP) */
    rt_lat_add(pi, ipaddr, NULL);
    /* Add a LOCAL route to the LPM for the IP address */
    rt_lpm_host_create(pi->rdidx, ipaddr, pi, RT_LPM_F_LOCAL);
    if (plen < 32) {
        /* Create a subnet-route and a host route */
        rt_ipv4_prefix_t prefix;
        prefix.addr = ipaddr;
        prefix.len = plen;
        /* Add a route to the LPM for the subnet */
        rt_lpm_t *srt = rt_lpm_find_or_create(pi->rdidx, prefix, pi);
        assert(srt != NULL);
        srt->flags |= RT_LPM_F_SUBNET;
        /* Add local IP address to route entry */
        srt->ifipa = ipaddr;
    }
}

rt_lpm_t *
rt_lpm_add_nexthop (rt_rd_t rdidx, rt_ipv4_addr_t ipaddr)
{
    rt_lpm_t *rt = rt_lpm_lookup(rdidx, ipaddr);
    if (rt == NULL) {
        fprintf(stderr, "ERROR: no route for (%u) %s\n",
            rdidx, rt_ipaddr_nr_str(ipaddr));
        return NULL;
    }
    rt_ipv4_prefix_t prefix;
    prefix.addr = ipaddr;
    prefix.len = 32;
    return rt_lpm_find_or_create(rdidx, prefix, rt->pi);
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
        n += sprintf(&str[n], " NH: (%u) %s",
            rt->nh_rdidx, rt_ipaddr_str(tmpstr, rt->nhipa));
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
        if (p->flags & RT_LPM_F_HAS_NEXTHOP) {
            // FIXME
        }
    }
}

/**********************************************************************/
/*  Address Resolution Table */

static sem_t rt_ipv4_ar_lock;

static rt_ipv4_ar_t rt_ipv4_ar_table[RT_IPV4_AR_TABLE_SIZE];

static inline int rt_ipv4_art_hash (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr)
{
    return ((pi->idx + ipaddr) % 5369565217 ) % RT_IPV4_AR_TABLE_SIZE;
}

void rt_ar_table_init (void)
{
    int rc = sem_init(&rt_ipv4_ar_lock, 1, 1);
    assert(rc == 0);
    int idx;
    for (idx = 0 ; idx < RT_IPV4_AR_TABLE_SIZE ; idx++)
    {
        rt_ipv4_ar_t *p = &rt_ipv4_ar_table[idx];
        memset(p, 0, sizeof(rt_ipv4_ar_t));
        p->pi = NULL;
        p->prev = p->next = p;
    }
}

rt_ipv4_ar_t *
rt_ipv4_ar_lookup (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr)
{
    int idx = rt_ipv4_art_hash(pi, ipaddr);
    rt_ipv4_ar_t  *hd = &rt_ipv4_ar_table[idx];
    rt_ipv4_ar_t *sp;
    for (sp = hd ; ; sp = sp->next) {
        if ((sp->pi == pi) && (sp->ipaddr == ipaddr))
            return sp;
        if (sp->next == hd)
            break;
    }
    return NULL;
}

rt_ipv4_ar_t *rt_ipv4_ar_find_or_create (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr)
{
    /* Allocate new entry (just in case) */
    rt_ipv4_ar_t *ap = (rt_ipv4_ar_t *) malloc(sizeof(rt_ipv4_ar_t));
    assert(ap != NULL);
    memset(ap, 0, sizeof(rt_ipv4_ar_t));

    int idx = rt_ipv4_art_hash(pi, ipaddr);
    rt_ipv4_ar_t *hd = &rt_ipv4_ar_table[idx];
    rt_ipv4_ar_t *sp;

    sem_wait(&rt_ipv4_ar_lock);
    for (sp = hd ; ; sp = sp->next) {
        if ((sp->pi == pi) && (sp->ipaddr == ipaddr))
            break;
        if (sp->next == hd) {
            if (hd->pi == NULL) {
                sp = hd;
            } else {
                /* Insert 'ap' at end of list */
                ap->next = hd;
                ap->prev = hd->prev;
                hd->prev->next = ap;
                hd->prev = ap;
                sp = ap;
                ap = NULL;
            }
            sp->pi = pi;
            sp->ipaddr = ipaddr;
            sp->flags = 0;
            break;
        }
    }
    sem_post(&rt_ipv4_ar_lock);


    /* If the ap was not used (ap != NULL), then relase it */
    free(ap);

    return sp;
}

int rt_ipv4_ar_get_pkt (rt_pkt_t *pkt, rt_ipv4_ar_t *ar)
{
    if (ar == NULL)
        return 0;
    int got_pkt = 0;
    sem_wait(&rt_ipv4_ar_lock);
    if (ar->flags & RT_AR_F_HAS_PKT) {
        memcpy(pkt, &ar->pkt, sizeof(rt_pkt_t));
        ar->flags &= ~RT_AR_F_HAS_PKT;
        memset(&ar->pkt, 0, sizeof(rt_pkt_t));
        got_pkt = 1;
    }
    sem_post(&rt_ipv4_ar_lock);
    return got_pkt;
}

int rt_ipv4_ar_set_pkt (rt_pkt_t pkt, rt_ipv4_ar_t *ar)
{
    if (ar == NULL)
        return 0;
    int added_pkt = 0;
    sem_wait(&rt_ipv4_ar_lock);
    if ((ar->flags & RT_AR_F_HAS_PKT) == 0) {
        memcpy(&ar->pkt, &pkt, sizeof(rt_pkt_t));
        ar->flags |= RT_AR_F_HAS_PKT;
        added_pkt = 1;
    }
    sem_post(&rt_ipv4_ar_lock);
    return added_pkt;
}

rt_ipv4_ar_t *
rt_ipv4_ar_learn (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr,
    rt_eth_addr_t hwaddr)
{
    rt_ipv4_ar_t *sp = rt_ipv4_ar_find_or_create(pi, ipaddr);
    assert(sp != NULL);

    sem_wait(&rt_ipv4_ar_lock);

    memcpy(sp->hwaddr, hwaddr, sizeof(rt_eth_addr_t));
    sp->flags |= RT_AR_F_HAS_HWADDR;

    sem_post(&rt_ipv4_ar_lock);

    return sp;
}

/**********************************************************************/
/*  Local Address Table */

static rt_lat_t rt_lat_table[RT_LAR_TABLE_SIZE];

static inline int rt_lat_db_hash (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr)
{
    return ((pi->idx + ipaddr) % 5369565217 ) % RT_LAR_TABLE_SIZE;
}

void rt_lat_init (void)
{
    int idx;
    for (idx = 0 ; idx < RT_LAR_TABLE_SIZE ; idx++)
    {
        rt_lat_t *p = &rt_lat_table[idx];
        p->pi = NULL;
        p->prev = p->next = p;
    }
}

rt_lat_t *
rt_lat_db_lookup (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr)
{
    int idx = rt_lat_db_hash(pi, ipaddr);
    rt_lat_t *hd = &rt_lat_table[idx];
    rt_lat_t *sp;
    for (sp = hd ; ; sp = sp->next) {
        if ((sp->pi == pi) && (sp->ipaddr == ipaddr))
            return sp;
        if (sp->next == hd)
            return NULL;
    }
}

rt_eth_addr_t *
rt_lat_get_eth_addr (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr)
{
    rt_lat_t *sp = rt_lat_db_lookup(pi, ipaddr);
    if (sp != NULL) {
        if (sp->flags & RT_LAR_F_USE_PORT_HWADDR)
            return &sp->pi->hwaddr;
        else
            return &sp->hwaddr;
    }
    return NULL;
}

rt_lat_t *rt_lat_add (rt_port_info_t *pi, rt_ipv4_addr_t ipaddr,
    rt_eth_addr_t *hwaddr)
{
    rt_lat_t *sp = rt_lat_db_lookup(pi, ipaddr);
    if (sp != NULL) {
        memcpy(sp->hwaddr, hwaddr, sizeof(rt_eth_addr_t));
        return sp;
    }
    int idx = rt_lat_db_hash(pi, ipaddr);
    rt_lat_t *hd = &rt_lat_table[idx];
    rt_lat_t *np;
    if (hd->pi == NULL) {
        /* 'head' entry is available */
        np = hd;
    } else {
        /* Allocate new entry */
        np = (rt_lat_t *) malloc(sizeof(rt_lat_t));
        assert(np != NULL);
    }
    /* Populate Entry */
    np->pi = pi;
    np->ipaddr = ipaddr;
    np->flags = 0;
    if (hwaddr == NULL) {
        hd->flags |= RT_LAR_F_USE_PORT_HWADDR;
    } else {
        memcpy(hd->hwaddr, hwaddr, sizeof(rt_eth_addr_t));
    }
    if (np != hd) {
        /* Insert new entry */
        np->next = hd;
        np->prev = hd->prev;
        hd->prev->next = np;
        hd->prev = np;
    }
    return np;
}

/**********************************************************************/
