'use strict';
// Normal authentication of the existing pinned MASTER administrator only.
// Writes an exclusive protected token file; never creates a fixture identity.
const fs=require('node:fs'), path=require('node:path'), crypto=require('node:crypto');
const MASTER='302ae5a70c403124f764cbc54229cfcd';
let phase='arguments';
function need(ok) {if (!ok) throw Error('failed');}
function privateRead(file) {
    const fd=fs.openSync(file,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW|fs.constants.O_NONBLOCK);
    try {const st=fs.fstatSync(fd); need(st.isFile()&&st.uid===0&&(st.mode&0o777)===0o600&&st.nlink===1&&st.size>0&&st.size<65536);
        return fs.readFileSync(fd,'utf8');} finally {fs.closeSync(fd);}
}
async function request(method, resource, token, data) {
    const response=await fetch('http://127.0.0.1:8000/v2/'+resource,
        {method,redirect:'error',signal:AbortSignal.timeout(10000),
         headers:{'Content-Type':'application/json',...(token?{'X-Auth-Token':token}:{})},
         body:data===undefined?undefined:JSON.stringify({data})});
    need(response.ok);
    let size=0;const chunks=[];
    for await (const chunk of response.body) {size+=chunk.length;need(size<=65536);chunks.push(chunk);}
    const body=JSON.parse(Buffer.concat(chunks).toString('utf8'));need(body.status==='success');return body;
}
async function main() {
    need(process.argv.length===4&&process.argv[2]==='--output'&&process.getuid()===0&&
        !process.env.NODE_OPTIONS&&!process.env.NODE_PATH);
    const output=process.argv[3], parent=path.dirname(output);
    need(path.isAbsolute(output)&&path.basename(output)==='admin-token'&&fs.realpathSync(parent)===parent);
    const st=fs.lstatSync(parent);need(st.isDirectory()&&!st.isSymbolicLink()&&st.uid===0&&(st.mode&0o777)===0o700);
    need(!fs.existsSync(output));
    phase='protected_config';
    const fields=new Map();
    for (const line of privateRead('/etc/kazoo/installer-secrets.env').split('\n')) {
        if (!line||line.startsWith('#')) continue;
        const pos=line.indexOf('=');need(pos>0);const key=line.slice(0,pos);need(!fields.has(key));fields.set(key,line.slice(pos+1));
    }
    const user=fields.get('KAZOO_MASTER_ADMIN_USER'), password=fields.get('KAZOO_MASTER_ADMIN_PASSWORD'),
        realm=fields.get('KAZOO_MASTER_ACCOUNT_REALM');need(user&&password&&realm);
    phase='authenticate_existing_admin';
    const auth=await request('PUT','user_auth',undefined,
        {credentials:crypto.createHash('md5').update(user+':'+password).digest('hex'),method:'md5',realm});
    need(auth.data?.account_id===MASTER&&typeof auth.auth_token==='string'&&/^[\x21-\x7e]{1,16384}$/.test(auth.auth_token));
    phase='verify_account';
    const account=(await request('GET','accounts/'+MASTER,auth.auth_token)).data;
    need(account?.id===MASTER&&account.realm===realm);
    phase='write_protected_token';
    const fd=fs.openSync(output,fs.constants.O_WRONLY|fs.constants.O_CREAT|fs.constants.O_EXCL|fs.constants.O_NOFOLLOW,0o600);
    try {fs.writeFileSync(fd,auth.auth_token+'\n');fs.fsyncSync(fd);} finally {fs.closeSync(fd);}
    console.log('PASS: existing local administrator authenticated; protected token file created');
}
if (require.main===module) main().catch(()=>{console.error('FAIL local administrator acceptance token: '+phase);process.exitCode=1;});
