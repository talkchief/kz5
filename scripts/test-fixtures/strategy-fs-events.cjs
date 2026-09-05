'use strict';
const assert=require('node:assert/strict');
function extract(text){const events=[];let offset=0;
    while(true){const begin=text.indexOf('RECV EVENT\n',offset);if(begin<0)break;const end=text.indexOf('\n\n',begin);if(end<0)return {events,rest:text.slice(begin)};
        const headers={};for(const line of text.slice(begin+11,end).split('\n')){const at=line.indexOf(':');if(at<0)continue;
            headers[line.slice(0,at)]=decodeURIComponent(line.slice(at+1).trim());}
        if(['CHANNEL_BRIDGE','CHANNEL_UNBRIDGE'].includes(headers['Event-Name']))events.push(headers);offset=end+2;}
    return {events,rest:text.slice(offset).slice(-100000)};}
function partner(event,caller,account){assert(event['variable_ecallmgr_Account-ID']===account,'Event account scope mismatch');
    if(event['Unique-ID']===caller)return event['Other-Leg-Unique-ID'];
    if(event['Other-Leg-Unique-ID']===caller)return event['Unique-ID'];return undefined;}
module.exports={extract,partner};
