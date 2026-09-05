/* Exercise the actual production app against a deterministic FS boundary.
 * The mock deliberately leaves CF_BRIDGED unset after successful intercept,
 * reproducing the asynchronous pending-bridge window of FreeSWITCH 1.11.3.
 */
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define SWITCH_UUID_FORMATTED_LENGTH 36
#define SWITCH_STANDARD_APP(name) static void name(switch_core_session_t *session, const char *data)
#define SWITCH_STATUS_SUCCESS 0
#define SWITCH_FALSE 0
#define SWITCH_MUTEX_NESTED 0
#define SWITCH_EVENT_CHANNEL_DESTROY 1
#define SWITCH_EVENT_SUBCLASS_ANY NULL
#define SWITCH_CAUSE_CALL_REJECTED 21
#define SWITCH_CAUSE_NO_ROUTE_DESTINATION 3
#define SWITCH_CAUSE_DESTINATION_OUT_OF_ORDER 27
#define SWITCH_CAUSE_LOSE_RACE 702
#define CF_BRIDGED 1
#define zstr(s) (!(s) || !*(s))
typedef pthread_mutex_t switch_mutex_t;
typedef int switch_event_node_t;
typedef struct channel {
    const char *account, *agent, *member;
    char token[37];
    int up, bridged, cause;
    void *private_data;
} switch_channel_t;
typedef struct session { const char *id; switch_channel_t channel; } switch_core_session_t;
typedef struct event { const char *owner, *member, *account, *token; } switch_event_t;
static struct { void *pool; } kazoo_globals;
static switch_core_session_t target;
static atomic_int bridge_attempts, allocated, token_seq, unbound;
static int intercept_result, locate_blocked;
static pthread_barrier_t barrier;
static void switch_mutex_lock(switch_mutex_t *m) { assert(!pthread_mutex_lock(m)); }
static void switch_mutex_unlock(switch_mutex_t *m) { assert(!pthread_mutex_unlock(m)); }
static void switch_mutex_init(switch_mutex_t **m, int flags, void *pool) {
    (void)flags; (void)pool; *m=malloc(sizeof(**m)); assert(*m); assert(!pthread_mutex_init(*m,NULL));
}
static switch_channel_t *switch_core_session_get_channel(switch_core_session_t *s) { return &s->channel; }
static const char *switch_core_session_get_uuid(switch_core_session_t *s) { return s->id; }
static const char *switch_str_nil(const char *s) { return s ? s : ""; }
static const char *switch_channel_get_variable(switch_channel_t *c, const char *key) {
    if (!strcmp(key,"ecallmgr_Account-ID")) return c->account;
    if (!strcmp(key,"ecallmgr_Agent-ID")) return c->agent;
    if (!strcmp(key,"ecallmgr_Member-Call-ID")) return c->member;
    if (!strcmp(key,"kz_intercept_claim_token")) return c->token;
    return NULL;
}
static void switch_copy_string(char *out, const char *in, size_t n) { assert(strlen(in)<n); strcpy(out,in); }
static void switch_channel_set_variable(switch_channel_t *c, const char *key, const char *v) {
    if (!strcmp(key,"kz_intercept_claim_token")) switch_copy_string(c->token,v,sizeof(c->token));
}
static int switch_channel_up(switch_channel_t *c) { return c->up; }
static int switch_channel_test_flag(switch_channel_t *c, int flag) { (void)flag; return c->bridged; }
static void *switch_channel_get_private(switch_channel_t *c, const char *key) { (void)key; return c->private_data; }
static void switch_channel_set_private(switch_channel_t *c, const char *key, void *p) { (void)key; c->private_data=p; }
static void *switch_core_session_alloc(switch_core_session_t *s, size_t n) { (void)s; atomic_fetch_add(&allocated,1); return calloc(1,n); }
static switch_core_session_t *switch_core_session_locate(const char *id) { return !locate_blocked && !strcmp(id,target.id) ? &target : NULL; }
static void switch_core_session_rwunlock(switch_core_session_t *s) { (void)s; }
static void switch_channel_hangup(switch_channel_t *c, int cause) { c->up=0; c->cause=cause; }
static void switch_uuid_str(char *out, size_t n) { snprintf(out,n,"%032d",atomic_fetch_add(&token_seq,1)+1); }
static int switch_ivr_intercept_session(switch_core_session_t *s, const char *id, int bleg) {
    (void)s; assert(!strcmp(id,target.id)); assert(!bleg); atomic_fetch_add(&bridge_attempts,1); return intercept_result;
}
static const char *switch_event_get_header(switch_event_t *e, const char *k) {
    if (!strcmp(k,"Unique-ID")) return e->owner;
    if (!strcmp(k,"variable_ecallmgr_Member-Call-ID")) return e->member;
    if (!strcmp(k,"variable_ecallmgr_Account-ID")) return e->account;
    if (!strcmp(k,"variable_kz_intercept_claim_token")) return e->token;
    return NULL;
}
static int switch_event_bind_removable(const char *name, int id, const char *sub, void (*f)(switch_event_t *), void *p, switch_event_node_t **node) {
    static int binding; (void)name; (void)id; (void)sub; (void)f; (void)p; *node=&binding; return 0;
}
static void switch_event_unbind(switch_event_node_t **n) { *n=NULL; atomic_fetch_add(&unbound,1); }
#include "kazoo_intercept.h"

static switch_core_session_t agent(const char *id) {
    switch_core_session_t s={.id=id,.channel={.account="account",.agent="agent",.member="caller@local",.up=1}}; return s;
}
static void reset(void) {
    free(target.channel.private_data);
    target=(switch_core_session_t){.id="caller@local",.channel={.account="account",.up=1}};
    atomic_store(&bridge_attempts,0); atomic_store(&allocated,0); intercept_result=0; locate_blocked=0;
}
static void *race(void *arg) { pthread_barrier_wait(&barrier); kz_intercept_function(arg,target.id); return NULL; }
static switch_event_t destroyed(switch_core_session_t *s) {
    return (switch_event_t){s->id,s->channel.member,s->channel.account,s->channel.token};
}
int main(void) {
    int round, i;
    kz_intercept_start();
    for (round=0; round<100; round++) {
        pthread_t threads[3]; switch_core_session_t a[3]={agent("a"),agent("b"),agent("c")};
        int winners=0, losers=0;
        reset(); assert(!pthread_barrier_init(&barrier,NULL,3));
        for (i=0;i<3;i++) assert(!pthread_create(&threads[i],NULL,race,&a[i]));
        for (i=0;i<3;i++) assert(!pthread_join(threads[i],NULL));
        assert(!pthread_barrier_destroy(&barrier));
        for (i=0;i<3;i++) { winners+=a[i].channel.up; losers+=(a[i].channel.cause==SWITCH_CAUSE_LOSE_RACE); }
        assert(winners==1 && losers==2 && atomic_load(&bridge_attempts)==1);
        assert(atomic_load(&allocated)==1 && target.channel.up && !target.channel.cause);
    }
    {
        switch_core_session_t a=agent("same-uuid"), b=agent("b"), c=agent("same-uuid");
        char old_token[37]; switch_event_t event;
        reset(); kz_intercept_function(&a,target.id); strcpy(old_token,a.channel.token);
        kz_intercept_function(&a,target.id);
        assert(a.channel.up && atomic_load(&bridge_attempts)==1 && !strcmp(old_token,a.channel.token));
        target.channel.bridged=1; kz_intercept_function(&a,target.id);
        assert(a.channel.up && atomic_load(&bridge_attempts)==1); target.channel.bridged=0;
        event=destroyed(&a); event.token="stale"; kz_intercept_destroy(&event);
        kz_intercept_function(&b,target.id); assert(b.channel.cause==SWITCH_CAUSE_LOSE_RACE);
        event.token=old_token; event.account="other"; kz_intercept_destroy(&event);
        assert(((kz_intercept_claim_t *)target.channel.private_data)->owner[0]);
        event.account="account"; locate_blocked=1; kz_intercept_destroy(&event);
        assert(((kz_intercept_claim_t *)target.channel.private_data)->owner[0]);
        locate_blocked=0; kz_intercept_destroy(&event);
        assert(!((kz_intercept_claim_t *)target.channel.private_data)->owner[0]);
        kz_intercept_function(&c,target.id); assert(c.channel.up);
        kz_intercept_destroy(&event); /* Old UUID's event must not clear new nonce. */
        assert(((kz_intercept_claim_t *)target.channel.private_data)->owner[0]);
        assert(atomic_load(&allocated)==1);
    }
    {
        const char *invalid[]={NULL,"","caller,hangup:all","caller' inline","caller\n"};
        reset();
        for (i=0;i<5;i++) { switch_core_session_t a=agent("a"); kz_intercept_function(&a,invalid[i]); assert(a.channel.cause==SWITCH_CAUSE_CALL_REJECTED); }
        { switch_core_session_t a=agent("a"); a.channel.account="other"; kz_intercept_function(&a,target.id); assert(a.channel.cause==SWITCH_CAUSE_CALL_REJECTED); }
        { switch_core_session_t a=agent("a"); a.channel.member="other"; kz_intercept_function(&a,target.id); assert(a.channel.cause==SWITCH_CAUSE_CALL_REJECTED); }
        assert(atomic_load(&bridge_attempts)==0 && target.channel.up);
    }
    {
        switch_core_session_t a=agent("a"), b=agent("b");
        reset(); intercept_result=-1; kz_intercept_function(&a,target.id);
        assert(a.channel.cause==SWITCH_CAUSE_DESTINATION_OUT_OF_ORDER);
        assert(!((kz_intercept_claim_t *)target.channel.private_data)->owner[0]);
        intercept_result=0; kz_intercept_function(&b,target.id); assert(b.channel.up);
    }
    {
        switch_core_session_t a=agent("a"), b=agent("b");
        reset(); target.channel.bridged=1; kz_intercept_function(&a,target.id);
        assert(a.channel.cause==SWITCH_CAUSE_LOSE_RACE && atomic_load(&bridge_attempts)==0);
        target.channel.bridged=0; remove_kz_dptools(); kz_intercept_function(&b,target.id);
        assert(b.channel.cause==SWITCH_CAUSE_LOSE_RACE && atomic_load(&bridge_attempts)==0 && atomic_load(&unbound)==1);
    }
    reset(); pthread_mutex_destroy(kz_intercept_mutex); free(kz_intercept_mutex);
    puts("PASS: 100 simultaneous 3-answer races, one winner, loser-only termination, bounded allocation, ownership, nonce, failure and shutdown cleanup");
    return 0;
}
