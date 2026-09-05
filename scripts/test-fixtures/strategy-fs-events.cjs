'use strict';
const assert=require('node:assert/strict');
function extract(text){const events=[];let offset=0;const prefix='INCOMING DATA [text/event-json]\n';
    while(true){const begin=text.indexOf(prefix,offset);if(begin<0)break;const start=text.indexOf('{',begin+prefix.length);
        if(start<0)return {events,rest:text.slice(begin)};
        let depth=0,string=false,escape=false,end=-1;for(let i=start;i<text.length;i++){const c=text[i];
            if(string){if(escape)escape=false;else if(c==='\\')escape=true;else if(c==='"')string=false;continue;}
            if(c==='"')string=true;else if(c==='{')depth++;else if(c==='}'&&--depth===0){end=i+1;break;}}
        if(end<0)return {events,rest:text.slice(begin)};
        const data=JSON.parse(text.slice(start,end)),headers={};
        for(const key of ['Event-Name','Event-Date-Timestamp','Unique-ID','Other-Leg-Unique-ID','Bridge-A-Unique-ID','Bridge-B-Unique-ID','variable_ecallmgr_Account-ID'])
            if(data[key]!==undefined)headers[key]=data[key];
        if(['CHANNEL_BRIDGE','CHANNEL_UNBRIDGE'].includes(headers['Event-Name']))events.push(headers);offset=end;}
    return {events,rest:text.slice(offset).slice(-100000)};}
function partner(event,caller,account){assert(event['variable_ecallmgr_Account-ID']===account,'Event account scope mismatch');
    if(event['Bridge-A-Unique-ID']===caller)return event['Bridge-B-Unique-ID'];
    if(event['Bridge-B-Unique-ID']===caller)return event['Bridge-A-Unique-ID'];
    if(event['Unique-ID']===caller)return event['Other-Leg-Unique-ID'];
    if(event['Other-Leg-Unique-ID']===caller)return event['Unique-ID'];return undefined;}
module.exports={extract,partner};
