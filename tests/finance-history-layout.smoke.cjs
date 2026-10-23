const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'..','settlement-history.js'),'utf8');
assert.match(source,/label:'レジ金変動履歴'/);
assert.match(source,/label:'経費履歴'/);
assert.match(source,/body\.appendChild\(config\.history\)/);
assert.match(source,/body\.appendChild\(all\)/);
assert.match(source,/full-history-button/);
assert.match(source,/レジ金の全体履歴/);
assert.match(source,/経費の全体履歴/);
console.log('PASS finance histories are ordered and full-history actions sit at each history bottom');

