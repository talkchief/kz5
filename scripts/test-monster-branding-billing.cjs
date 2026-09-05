'use strict';
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), assert = require('node:assert/strict');
const source = process.argv[2] || '/usr/local/src/kazoo5-installer/monster-ui';
const _ = require(path.join(source, 'node_modules/lodash'));
function fixture(branding, braintree) {
    const requests = [], images = [], icons = [];
    const config = {api: {default: 'https://api.example.invalid/v2/'},
        whitelabel: {fetchFromApi: branding, bookkeepers: {braintree}}};
    const monster = {config, apps: {}, util: {isReseller: () => true, isMasquerading: () => false, isAdmin: () => true}};
    let waterfalls = 0, parallels = 0;
    monster.waterfall = (steps, callback) => {
        waterfalls++;
        let index = 0;
        function next(error, data) { if(error || index === steps.length) return callback(error, data); const step = steps[index++]; index === 1 ? step(next) : step(data, next); }
        next(null);
    };
    monster.parallel = () => { parallels++; };
    const container = {find() {return {css(name,value) {assert.equal(name,'background-image'); images.push(value);}};}};
    const document = {createElement: () => ({}), getElementById: () => null, head: {appendChild: value => icons.push(value.href)}};
    function load(file) {
        let app;
        vm.runInNewContext(fs.readFileSync(path.join(source,file),'utf8'), {
            window: {location: {hostname: 'ui.example.invalid'}}, document,
            define(factory) {app=factory(name=>name==='lodash'?_:name==='monster'?monster:name==='jquery'?()=>container:{});}
        });
        app.callApi = args => {requests.push(args.resource); args.success?.({data:{credit_cards:[]}});};
        return app;
    }
    const core=load('src/apps/core/app.js');monster.apps.core=core;
    const auth=load('src/apps/auth/app.js');
    const billing=load('src/apps/myaccount/submodules/billing/billing.js');
    const card=load('src/apps/myaccount/submodules/creditCard/creditCard.js');
    card.billingGetBillingData=billing.billingGetBillingData.bind(billing);
    return {core,auth,billing,card,container,requests,images,icons,config,
        get waterfalls(){return waterfalls;},get parallels(){return parallels;}};
}
{
    const f=fixture(false,false);let callbacks=0;
    f.core.load(()=>callbacks++);f.core.displayLogo(f.container);f.core.displayFavicon();f.auth.renderLogo(f.container,()=>callbacks++);
    assert.equal(callbacks,2);assert.deepEqual(f.requests,[]);
    assert(f.images[0].includes('apps/core/style/static/images/logo.svg'));
    assert(f.images[1].includes('apps/auth/style/static/images/logo.svg'));
    assert.deepEqual(f.icons,['apps/core/style/static/images/favicon.png']);
    f.config.whitelabel.logoPath='custom/logo.svg';f.config.whitelabel.faviconPath='custom/icon.png';
    f.core.displayLogo(f.container);f.auth.renderLogo(f.container,()=>{});f.core.displayFavicon();
    assert(f.images.slice(-2).every(value=>value.includes('custom/logo.svg')));assert.equal(f.icons.at(-1),'custom/icon.png');
    f.billing.billingGetBillingData((error,result)=>{assert.equal(error,null);assert.equal(Object.keys(result).length,0);});
    f.card.creditCardCheckStatus();assert.equal(f.waterfalls,0);assert.equal(f.parallels,0);assert.deepEqual(f.requests,[]);
}
{
    const f=fixture(true,true);f.core.load(()=>{});f.core.displayLogo(f.container);f.core.displayFavicon();f.auth.renderLogo(f.container,()=>{});
    assert.deepEqual(f.requests,['whitelabel.getByDomain','whitelabel.getLogoByDomain','whitelabel.getIconByDomain','whitelabel.getLogoByDomain']);
    f.billing.billingGetBillingData(()=>{});assert.equal(f.requests.at(-1),'billing.get');assert.equal(f.waterfalls,1);
    f.card.creditCardCheckStatus();assert.equal(f.parallels,1);
}
{
    const f=fixture(true,false);
    f.core.callApi=args=>{f.requests.push(args.resource);args.error({status:404});};
    f.core.load(()=>{});f.core.displayLogo(f.container);f.core.displayFavicon();f.auth.renderLogo(f.container,()=>{});
    assert.deepEqual(f.requests,['whitelabel.getByDomain'],'An absent remote profile must not cascade into asset probes');
}
console.log('PASS local branding/default/custom assets without probes; remote branding retained; missing profile stops asset cascade; disabled billing makes no payment requests; configured billing retained');
