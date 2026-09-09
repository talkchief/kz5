'use strict';
const assert = require('node:assert/strict');
module.exports = async (page, origin, account) => {
    assert.equal(origin, 'https://kz5-dev.talkchief.io');
    assert.equal(account, 'adecbb84fbe9e06902a76731914d1943');
    const result = await page.evaluate(async () => {
        const checks = [], token = monster.apps.auth.getAuthToken();
        const socket = new WebSocket('wss://' + location.host + '/websocket');
        let phase = 'connect', sequence = 0;
        const opened = new Promise((resolve, reject) => {
            const timer = setTimeout(() => reject(new Error('connect-timeout')), 10000);
            socket.onopen = () => { clearTimeout(timer); resolve(); };
            socket.onerror = () => { clearTimeout(timer); reject(new Error('connect-failed')); };
        });
        async function command(auth) {
            const request_id = 'command-auth-' + (++sequence);
            return new Promise((resolve, reject) => {
                const timer = setTimeout(() => { socket.removeEventListener('message', receive); reject(new Error('reply-timeout')); }, 10000);
                function receive(event) {
                    let reply; try { reply = JSON.parse(event.data); } catch (_) { return; }
                    if (reply.request_id !== request_id) return;
                    clearTimeout(timer); socket.removeEventListener('message', receive); resolve(reply);
                }
                socket.addEventListener('message', receive);
                socket.send(JSON.stringify({action: 'ping', request_id, ...(auth === undefined ? {} : {auth_token: auth})}));
            });
        }
        function expect(condition) { if (!condition) throw new Error('unexpected-result'); }
        try {
            await opened;
            phase = 'anonymous-denial'; expect((await command()).status === 'error'); checks.push(phase);
            phase = 'valid-native-ping'; let reply = await command(token);
            expect(reply.status === 'success' && reply.data.response === 'pong'); checks.push(phase);
            phase = 'cached-valid-native-ping'; reply = await command();
            expect(reply.status === 'success' && reply.data.response === 'pong'); checks.push(phase);
            phase = 'changed-token-denial'; reply = await command('not-a-valid-token');
            expect(reply.status === 'error' && reply.data.errors.includes('reconnect to change authentication token')); checks.push(phase);
            phase = 'original-identity-retained'; reply = await command(token);
            expect(reply.status === 'success' && reply.data.response === 'pong'); checks.push(phase);
            return {status: 'PASS', checks};
        } catch (_) { return {status: 'FAIL', phase, checks}; }
        finally { socket.close(); }
    });
    console.log(JSON.stringify({...result, scope: 'real development admin JWT, WSS and native ping; no subscriptions, calls or account writes'}));
    assert.equal(result.status, 'PASS');
};
