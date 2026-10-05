"""Exercise the actual embedded bridge with a browser mock, without real credentials."""
import json
import pathlib
import re
import subprocess

source = pathlib.Path('NNPMengoBridge.xm').read_text(encoding='utf8')
literal = source.split('NSString *script = ', 1)[1].split(';\n        [content addUserScript:', 1)[0]
script = ''.join(json.loads(part) for part in re.findall(r'"(?:\\.|[^"\\])*"', literal))
test = r'''
const assert = require('node:assert/strict');
class Storage { constructor(){this.values={};} getItem(k){return this.values[k]??null;} setItem(k,v){this.values[k]=String(v);} removeItem(k){delete this.values[k];} clear(){this.values={};} }
global.Storage=Storage;global.localStorage=new Storage();
Object.defineProperty(global,'navigator',{value:{userAgent:'fixture-mobile-agent'}});
localStorage.setItem('ek_login_token','fixture+token');
global.XMLHttpRequest=class{open(){this.opened=true;}};
const messages=[];global.window={webkit:{messageHandlers:{nnpMengoSession:{postMessage:m=>messages.push(m)}}},addEventListener:()=>{}};
eval(SCRIPT);
assert.equal(messages.length,1);assert.equal(messages[0].token,'fixture+token');
assert.equal(messages[0].agent,'fixture-mobile-agent');
localStorage.setItem('unrelated','ignored');assert.equal(messages.length,1);
let xhr=new XMLHttpRequest();xhr.open('POST','https://men-go.tw/Platform/Htmlv2/MQRCode');
assert.equal(messages.at(-1).endpoint,'MQRCode');assert.equal(xhr.opened,true);
let count=messages.length;xhr.open('POST','https://other.example/Platform/Htmlv2/QRCode');assert.equal(messages.length,count);
localStorage.setItem('ek_login_token','second');assert.equal(messages.at(-1).token,'second');
localStorage.removeItem('ek_login_token');assert.equal(messages.at(-1).token,'');
localStorage.setItem('ek_login_token','third');localStorage.clear();assert.equal(messages.at(-1).token,'');
count=messages.length;eval(SCRIPT);assert.equal(messages.length,count);
console.log('MeN Go bridge login, endpoint, logout and deduplication tests passed');
'''.replace('SCRIPT', json.dumps(script))
subprocess.run(['node', '-e', test], check=True)
