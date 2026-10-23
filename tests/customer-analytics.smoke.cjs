const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'..','analytics-details.js'),'utf8');
assert.match(source,/function customerVisitStats\(\)/);
assert.match(source,/Math\.max\(14,Math\.round\(pace\*1\.5\)\)/);
assert.match(source,/顧客分析：最近来ていない客/);
assert.match(source,/顧客分析：曜日別によく来る客/);
assert.match(source,/item\.weekdayCounts\[index\]\/item\.total\*100/);
console.log('PASS customer lapse and preferred-weekday analytics');

