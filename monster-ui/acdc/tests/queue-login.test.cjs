'use strict';
// Offline AMD/state/DOM-event mocks only. No browser, HTTP, RPC or credentials.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),source=fs.readFileSync(path.join(root,'app.js'),'utf8');
const lodash=require(require.resolve('lodash',{paths:[process.cwd()]}));
const Handlebars=require(require.resolve('handlebars',{paths:[process.cwd()]}));
const strings=JSON.parse(fs.readFileSync(path.join(root,'i18n/en-US.json'),'utf8'));
const A='a'.repeat(32),B='b'.repeat(32),U='1'.repeat(32),V='2'.repeat(32),Q='3'.repeat(32),R='4'.repeat(32);
const plain=x=>JSON.parse(JSON.stringify(x));let groups=0;
function test(name,run){run();console.log('PASS '+(++groups)+' '+name);}
class Element{
 constructor(){this.values={};this.props={};this.events={};this.children={};this.value='';this.options=[];}
 find(key){return this.children[key]||(this.children[key]=new Element());}
 data(key,value){if(arguments.length===1)return this.values[key];this.values[key]=value;return this;}
 prop(key,value){if(arguments.length===1)return this.props[key];this.props[key]=value;return this;}
 val(value){if(!arguments.length)return this.value;this.value=value;return this;}
 text(value){if(!arguments.length)return this.textValue;this.textValue=value;return this;}
 html(value){this.htmlValue=value;return this;}
 on(name,fn){this.events[name]=fn;return this;}
 trigger(name){if(this.events[name])this.events[name].call(this);return this;}
 filter(){return this;}
 appendTo(target){target.options.push({value:this.value,text:this.textValue});return this;}
 closest(){return this;}
 dialog(command){assert.equal(command,'close');this.closed=true;this.closeHandler();return this;}
}
function fixture(){
 let app,clock=100000,seq=0;const timers=new Map(),requests=[],content=new Element(),view=new Element(),dialog=new Element();
 const $=value=>typeof value==='string'?new Element():value;$.trim=x=>String(x).trim();
 const monster={apps:{},ui:{dialog(node,options){assert.equal(node,content);assert.equal(typeof options.onClose,'function');assert.equal(options.close,undefined);dialog.closeHandler=options.onClose;return dialog;}}};
 const context={define:factory=>{app=factory(name=>name==='jquery'?$:name==='lodash'?lodash:monster);},Date:{now:()=>clock},Math,
  setTimeout(fn,delay){const id=++seq;timers.set(id,{fn,delay});return id;},clearTimeout(id){timers.delete(id);}};
 vm.runInNewContext(source,context,{filename:path.join(root,'app.js')});app.accountId=A;app.appFlags.acdc.currentTab='agents';app.appFlags.acdc.requestGeneration=1;
 app.i18n.active=()=>strings;app.getTemplate=options=>options.name==='agent-queue-login'?content:options;
 view.data('agent-inventory',[{id:U,first_name:'Ada',queues:[Q]},{id:V,first_name:'Other',queues:[R]}]);view.data('queue-inventory',[{id:Q,name:'Support'},{id:R,name:'Sales'}]);
 const originalRender=app.renderAgentQueueSessions;app.renderAgentQueueSessions=()=>{};
 let memberships=[Q],queues=[{id:Q,name:'Support'},{id:R,name:'Sales'}],getReply,postReply,postError,postDeferred;
 const pending={account_id:A,agent_id:U,queue_id:Q,action:'login',runtime_only:true,state:'pending',confirmed:false,runtime_member:false,runtime_observed:true,agent_status:'ready'};
 getReply={...pending};postReply={account_id:A,agent_id:U,queue_id:Q,action:'login',runtime_only:true,state:'pending',confirmed:false};
 app.requestCompleteList=(resource,data,callback)=>{requests.push({resource,data:plain(data),read:true});callback(null,resource==='acdc.agents.queueMemberships'?memberships:queues);};
 app.request=(resource,data,callback)=>{requests.push({resource,data:plain(data)});if(resource==='acdc.agents.queueLoginStatus')callback(null,getReply);
  else if(resource==='acdc.agents.queueLogin'){if(postDeferred){postDeferred=callback;return;}callback(postError,postReply);}else throw Error('Unexpected request: '+resource);};
 return {app,content,view,dialog,timers,requests,pending,originalRender,
  advance(ms){clock+=ms;},setGet(value){getReply=value;},setPost(value,error){postReply=value;postError=error;},deferPost(){postDeferred=true;},finishPost(){postDeferred(null,postReply);},
  setMemberships(v){memberships=v;},setQueues(v){queues=v;},open(){app.openAgentQueueLogin(view,U,1,A);},select(id=Q){content.find('.acdc-login-queue').val(id).trigger('change');},
  click(){content.find('.acdc-confirm-queue-login').trigger('click');},check(){content.find('.acdc-check-queue-login').trigger('click');},
  poll(){const item=[...timers].find(([,v])=>v.delay===1000);if(!item)return false;timers.delete(item[0]);item[1].fn();return true;}};
}
test('queue-only routes and exact read query',()=>{const {app}=fixture();assert.equal(app.requests['acdc.agents.queueLogin'].verb,'POST');assert.equal(app.requests['acdc.agents.queueMemberships'].verb,'GET');
 assert.equal(app.requests['acdc.agents.queueLoginStatus'].url,'accounts/{accountId}/agents/{agentId}/queue_status?runtime_only=true&queue_id={queueId}&action=login');});
test('only configured memberships become choices',()=>{const {app}=fixture();assert.deepEqual(plain(app.queueLoginChoices([Q],[{id:Q,name:'Support'},{id:R,name:'Sales'}])),{valid:true,choices:[{id:Q,name:'Support'}]});
 assert.deepEqual(plain(app.queueLoginChoices([],[{id:Q,name:'Support'}])),{valid:true,choices:[]});});
test('malformed, orphan, duplicate and oversized inventories fail closed',()=>{const {app}=fixture();for(const [m,q]of [[null,[]],[[Q],null],[[Q],[]],[[Q,Q],[{id:Q}]],[[Q],[{id:Q},{id:Q}]],[[Q],[{id:'../queue'}]],[Array(1001).fill(Q),[{id:Q}]]])assert.equal(app.queueLoginChoices(m,q).valid,false);});
test('fresh matching runtime membership confirms even when globally paused',()=>{const f=fixture();const p=f.app.queueLoginProof({...f.pending,state:'confirmed',confirmed:true,runtime_member:true,agent_status:'paused'},U,Q);
 assert.deepEqual(plain(p),{state:'confirmed',agentStatus:'paused'});});
test('legacy, mismatched and unobserved responses never confirm',()=>{const f=fixture(),good={...f.pending,state:'confirmed',confirmed:true,runtime_member:true};
 for(const p of [[Q],{}, {...good,account_id:B},{...good,agent_id:V},{...good,queue_id:R},{...good,action:'logout'},{...good,runtime_only:undefined},{...good,runtime_observed:false},{...good,runtime_member:false},{...good,confirmed:'true'},{...good,account_id:undefined}])assert.equal(f.app.queueLoginProof(p,U,Q),null);});
test('session state is isolated by account, agent and queue and expires',()=>{const f=fixture();f.app.agentQueueSession(U,Q,{state:'confirmed'});assert.equal(f.app.agentQueueSession(U,Q).state,'confirmed');
 assert.equal(f.app.agentQueueSession(V,Q).state,'unconfirmed');assert.equal(f.app.agentQueueSession(U,R).state,'unconfirmed');f.app.accountId=B;assert.equal(f.app.agentQueueSession(U,Q).state,'unconfirmed');
 f.app.accountId=A;f.advance(30001);assert.equal(f.app.agentQueueSession(U,Q).state,'unconfirmed');});
test('accepted POST stays pending and uses only runtime-only selected-agent login',()=>{const f=fixture();let done=false;f.app.sendAgentQueueLogin(U,Q,error=>{assert(!error);done=true;});assert(done);
 assert.deepEqual(f.requests,[{resource:'acdc.agents.queueLogin',data:{agentId:U,data:{action:'login',queue_id:Q,runtime_only:true}}}]);assert.equal(f.app.agentQueueSession(U,Q).state,'pending');assert.equal(f.app.agentQueueSession(V,Q).state,'unconfirmed');});
test('POST timeout or premature confirmed response cannot report success',()=>{for(const error of ['timeout',undefined]){const f=fixture();f.setPost({...f.pending,state:'confirmed',confirmed:true},error);let failure;f.app.sendAgentQueueLogin(U,Q,e=>failure=e);assert(failure);assert.equal(f.app.agentQueueSession(U,Q).state,'pending');}});
test('global ready and persisted membership are not queue runtime proof',()=>{const f=fixture();let result;f.app.checkAgentQueueLogin(U,Q,(e,p)=>result=p);assert.equal(result.state,'unconfirmed');f.setGet([Q]);f.app.checkAgentQueueLogin(U,Q,e=>assert(e));assert.equal(f.app.agentQueueSession(U,Q).state,'unconfirmed');});
test('dialog opens without preselection or login write, even with one choice',()=>{const f=fixture();f.open();assert.equal(f.content.find('.acdc-login-queue').val(),'');assert.equal(f.content.find('.acdc-login-queue').options.length,1);f.click();
 assert(f.requests.every(r=>r.read));assert.equal(f.content.find('.acdc-confirm-queue-login').prop('disabled'),true);f.dialog.dialog('close');assert(f.requests.every(r=>r.read));});
test('empty eligible set disables submit and does not assign roster',()=>{const f=fixture();f.setMemberships([]);f.open();f.select(Q);f.click();assert(f.requests.every(r=>r.read));assert.equal(f.content.find('.acdc-confirm-queue-login').prop('disabled'),true);});
test('unsupported legacy runtime GET blocks submit',()=>{const f=fixture();f.setGet([Q]);f.open();f.select();f.click();assert(!f.requests.some(r=>r.resource==='acdc.agents.queueLogin'));assert.equal(f.content.find('.acdc-confirm-queue-login').prop('disabled'),true);});
test('explicit selection reads first and submits one exact runtime login',()=>{const f=fixture();f.open();f.select();assert(!f.requests.some(r=>r.resource==='acdc.agents.queueLogin'));f.click();f.click();
 const writes=f.requests.filter(r=>r.resource==='acdc.agents.queueLogin');assert.equal(writes.length,1);assert.deepEqual(writes[0].data,{agentId:U,data:{action:'login',queue_id:Q,runtime_only:true}});
 assert(f.requests.every(r=>!r.resource.includes('setStatus')&&!r.resource.includes('updateRoster')));});
test('duplicate click during in-flight POST is suppressed',()=>{const f=fixture();f.deferPost();f.open();f.select();f.click();f.click();assert.equal(f.requests.filter(r=>r.resource==='acdc.agents.queueLogin').length,1);f.finishPost();});
test('bounded six post-command checks never re-send login',()=>{const f=fixture();f.open();f.select();f.click();let polls=0;while(f.poll()){assert(++polls<=5);}assert.equal(polls,5);
 assert.equal(f.requests.filter(r=>r.resource==='acdc.agents.queueLoginStatus').length,7);assert.equal(f.requests.filter(r=>r.resource==='acdc.agents.queueLogin').length,1);assert.equal(f.app.agentQueueSession(U,Q).state,'pending');
 assert.equal(f.content.find('.acdc-check-queue-login').prop('disabled'),false);assert.equal(f.content.find('.acdc-confirm-queue-login').prop('disabled'),true);});
test('check again can confirm without another command; table proof expires',()=>{const f=fixture();f.open();f.select();f.click();while(f.poll()){}f.setGet({...f.pending,state:'confirmed',confirmed:true,runtime_member:true});f.check();
 assert.equal(f.app.agentQueueSession(U,Q).state,'confirmed');assert.equal(f.requests.filter(r=>r.resource==='acdc.agents.queueLogin').length,1);f.advance(31001);for(const [id,timer]of [...f.timers])if(timer.delay===31000){f.timers.delete(id);timer.fn();}
 assert.equal(f.app.agentQueueSession(U,Q).state,'unconfirmed');});
test('dialog close cancels read polling; account switch prevents stale proof',()=>{const f=fixture();f.open();f.select();f.click();const n=f.requests.length;f.dialog.dialog('close');assert.equal(f.poll(),false);assert.equal(f.requests.length,n);
 let callback;f.app.request=(r,d,cb)=>{callback=cb;};f.app.checkAgentQueueLogin(U,Q,()=>assert.fail('Stale account callback'));f.app.accountId=B;callback(null,{...f.pending,state:'confirmed',confirmed:true,runtime_member:true});assert.equal(f.app.agentQueueSession(U,Q).state,'unconfirmed');});
test('old global status handler explicitly rejects login',()=>{const f=fixture();f.app.bindAgentEvents(f.view,1,A);const button=new Element();button.data('id',U).data('status','login');f.view.find('.acdc-agent-action').events.click.call(button);assert.deepEqual(f.requests,[]);});
test('complete-list envelope refuses pagination before queue choice',()=>{const f=fixture();const requests=[];let app;vm.runInNewContext(source,{define:factory=>app=factory(name=>name==='jquery'?Object.assign(()=>{}, {trim:String}):name==='lodash'?lodash:{}),Date,Math,setTimeout,clearTimeout});app.i18n.active=()=>strings;
 app.requestEnvelope=(r,d,cb)=>cb(null,{status:'success',data:[Q],next_start_key:'more'});app.requestCompleteList('acdc.agents.queueMemberships',{},error=>requests.push(error));assert(requests[0]);});
test('templates separate global status and escape queue and agent labels',()=>{const table=fs.readFileSync(path.join(root,'views/agents.html'),'utf8');assert(table.includes('acdc-agent-queue-login'));assert(!table.includes('data-status="login"'));assert(table.includes('agents.globalStatus'));
 const dialog=Handlebars.compile(fs.readFileSync(path.join(root,'views/agent-queue-login.html'),'utf8'))({agentName:'<script>x</script>',i18n:strings});assert(dialog.includes('&lt;script&gt;'));assert(dialog.includes('role="status"'));assert(dialog.includes('<option value="">'));
 const rows=Handlebars.compile(fs.readFileSync(path.join(root,'views/agent-queue-sessions.html'),'utf8'))({items:[{name:'<b>Queue</b>',state:'pending',label:'Pending'}]});assert(rows.includes('&lt;b&gt;Queue&lt;/b&gt;'));});
console.log(JSON.stringify({result:'PASS',groups,network:false,browser:false,live_writes:false}));
