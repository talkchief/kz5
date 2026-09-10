'use strict';
const fs=require('node:fs'), path=require('node:path'), os=require('node:os');
const cp=require('node:child_process'), assert=require('node:assert/strict'), test=require('node:test');
const patch=path.join(__dirname,'patches/freeswitch-durable-media-admission.patch');
const text=fs.readFileSync(patch,'utf8');
// Compile the actual added production functions, not a separate implementation.
const added=text.split('\n').filter(l=>l.startsWith('+')&&!l.startsWith('+++')).map(l=>l.slice(1)).join('\n');
function extract(signature){
    const start=added.indexOf(signature);assert(start>=0);const open=added.indexOf('{',start);
    let depth=0;
    for(let i=open;i<added.length;i++){if(added[i]==='{')depth++;if(added[i]==='}'&&--depth===0)return added.slice(start,i+1);}
    throw Error('Missing production function body');
}
test('durable gate is inside the allocation lock and precedes insertion/limit bypass',()=>{
    assert(text.includes(' \tswitch_mutex_lock(runtime.session_hash_mutex);\n+\tif (kazoo_maintenance_marker_state() != 0)'));
    assert(text.includes('+\t\tswitch_mutex_unlock(runtime.session_hash_mutex);\n+\t\tUNPROTECT_INTERFACE(endpoint_interface);\n+\t\treturn NULL;'));
    assert(text.includes(' \tif (use_uuid && switch_core_hash_find(session_manager.session_table, use_uuid))'));
    assert(text.includes('"maintenance_check"'));
});
test('production marker validation and native inventory barrier',()=>{
    assert.equal(process.getuid(),0,'Root required for the root-owned marker contract');
    const dir=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-media-gate-'));
    const file=path.join(dir,'test.c'),bin=path.join(dir,'test');
    const source=String.raw`
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
static const char *root;
static int fail_io;
static int fixture_lstat(const char *name, struct stat *st) {
 char buf[1024];const char *prefix="/etc/kazoo5-maintenance";
 assert(strncmp(name,prefix,strlen(prefix))==0);
 if(fail_io){errno=EIO;return -1;}
 assert(snprintf(buf,sizeof(buf),"%s%s",root,name+strlen(prefix))<(int)sizeof(buf));
 return lstat(buf,st);
}
#define lstat fixture_lstat
#define SWITCH_DECLARE(type) type
static pthread_mutex_t mutex=PTHREAD_MUTEX_INITIALIZER;
static struct {pthread_mutex_t *session_hash_mutex;} runtime={&mutex};
static struct {uint32_t session_count;} session_manager;
#define switch_mutex_lock(p) assert(pthread_mutex_lock(p)==0)
#define switch_mutex_unlock(p) assert(pthread_mutex_unlock(p)==0)
`+extract('static int kazoo_maintenance_marker_state(void)')+'\n'+
extract('SWITCH_DECLARE(int) switch_core_session_maintenance_check(uint32_t *sessions)')+String.raw`
static atomic_int entered,finished;
static void *observer(void *unused){
 uint32_t count=0;(void)unused;atomic_store(&entered,1);
 assert(switch_core_session_maintenance_check(&count)==1);assert(count==7);
 atomic_store(&finished,1);return NULL;
}
static void marker(const char *p, mode_t mode, int bytes){
 int fd=open(p,O_WRONLY|O_CREAT|O_EXCL,mode);assert(fd>=0);
 if(bytes){assert(write(fd,"x",1)==1);}
 assert(close(fd)==0);assert(chmod(p,mode)==0);
}
int main(int argc,char **argv){
 char file[1024],link[1024];uint32_t count=99;pthread_t thread;
 assert(argc==2);root=argv[1];
 assert(snprintf(file,sizeof(file),"%s/media.closed",root)<(int)sizeof(file));
 assert(snprintf(link,sizeof(link),"%s/extra",root)<(int)sizeof(link));
 assert(kazoo_maintenance_marker_state()==0); /* directory absent */
 assert(mkdir(root,0755)==0);assert(chmod(root,0755)==0);
 assert(switch_core_session_maintenance_check(&count)==0&&count==0);
 marker(file,0644,1);assert(kazoo_maintenance_marker_state()==1);
 assert(chmod(file,0600)==0);assert(kazoo_maintenance_marker_state()==-1);
 assert(chmod(file,0644)==0);assert(chown(file,12345,12345)==0);
 assert(kazoo_maintenance_marker_state()==-1);assert(chown(file,0,0)==0);
 assert(linkat(AT_FDCWD,file,AT_FDCWD,link,0)==0);
 assert(kazoo_maintenance_marker_state()==-1);assert(unlink(link)==0);
 assert(unlink(file)==0);marker(file,0644,0);
 assert(kazoo_maintenance_marker_state()==-1);assert(unlink(file)==0);
 assert(symlink("absent-target",file)==0);assert(kazoo_maintenance_marker_state()==-1);
 assert(unlink(file)==0);assert(mkdir(file,0755)==0);
 assert(kazoo_maintenance_marker_state()==-1);assert(rmdir(file)==0);
 assert(chmod(root,0777)==0);assert(kazoo_maintenance_marker_state()==-1);
 assert(chmod(root,0755)==0);fail_io=1;assert(kazoo_maintenance_marker_state()==-1);fail_io=0;
 /* The observation waits for a prior allocation's critical section. */
 switch_mutex_lock(runtime.session_hash_mutex);
 assert(pthread_create(&thread,NULL,observer,NULL)==0);
 while(!atomic_load(&entered))usleep(1000);
 usleep(20000);assert(!atomic_load(&finished));
 marker(file,0644,1);session_manager.session_count=7;
 switch_mutex_unlock(runtime.session_hash_mutex);
 assert(pthread_join(thread,NULL)==0);assert(atomic_load(&finished));
 assert(unlink(file)==0);assert(switch_core_session_maintenance_check(&count)==0&&count==7);
 assert(rmdir(root)==0);puts("PASS native marker cases and serialized inventory barrier");return 0;
}
`;
    try{
        fs.writeFileSync(file,source,{flag:'wx',mode:0o600});
        cp.execFileSync('cc',['-std=gnu11','-Wall','-Wextra','-Werror','-pthread',file,'-o',bin],{stdio:'pipe',timeout:15000});
        const out=cp.execFileSync(bin,[path.join(dir,'state')],{encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:5000});
        assert(out.includes('PASS native marker cases'));
    }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
