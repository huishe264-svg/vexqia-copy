const assert=require('node:assert/strict');
const path=require('node:path');
const {chromium}=require('C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});try{
 const page=await browser.newPage({viewport:{width:390,height:844}});
 await page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',r=>r.fulfill({contentType:'application/javascript',body:'window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};'}));
 await page.route('https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js',r=>r.fulfill({contentType:'application/javascript',body:'window.Chart=class{constructor(){}destroy(){}update(){}};'}));
 await page.goto('file:///'+path.resolve(__dirname,'../index.html').replaceAll('\\','/'));
 const result=await page.evaluate(()=>{const first=document.querySelector('.sale-extra-amount');first.value='1280';first.dispatchEvent(new Event('input'));$('addSaleExtraAmount').click();const inputs=document.querySelectorAll('.sale-extra-amount');inputs[1].value='760';inputs[1].dispatchEvent(new Event('input'));$('addSaleExtraAmount').click();document.querySelectorAll('.sale-extra-amount')[2].value='500';saleExtraAmounts.calculate();const before={rows:document.querySelectorAll('.sale-extra-amount').length,sum:$('extraAmount').value,label:$('saleExtraTotal').textContent,type:$('extraAmount').type,width:document.documentElement.scrollWidth};resetInputImproved();return{before,afterRows:document.querySelectorAll('.sale-extra-amount').length,afterSum:$('extraAmount').value}});
 assert.deepEqual(result.before,{rows:3,sum:'2540',label:'¥2,540',type:'hidden',width:390});assert.equal(result.afterRows,1);assert.equal(result.afterSum,'0');console.log('PASS: multiple sale extras calculate, preserve hidden total, reset, and fit mobile width.');
}finally{await browser.close()}})().catch(e=>{console.error(e);process.exit(1)});
