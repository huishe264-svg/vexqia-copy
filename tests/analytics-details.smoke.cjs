const assert=require('node:assert/strict');
const path=require('node:path');
const fs=require('node:fs');
const {chromium}=require('C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844}});const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',route=>route.fulfill({contentType:'application/javascript',body:'window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};'}));
  await page.route('https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js',route=>route.fulfill({contentType:'application/javascript',body:'window.Chart=class{constructor(){}destroy(){}};'}));
  await page.goto('file:///'+path.resolve(__dirname,'../index.html').replaceAll('\\','/'));
  const result=await page.evaluate(()=>{
   currentAuthUser={id:'owner'};currentStoreMember={user_id:'owner',role:'owner'};storeId='store';platformAdminMode=false;
   employees=[{id:'e1',name:'オーナー'},{id:'e2',name:'店長'}];
   customers=[{id:'c1',name:'田中さん',is_active:true},{id:'c2',name:'佐藤さん',is_active:true}];
   sales=[
    {id:'s1',business_date:'2026-10-01',customer_id:'c1',employee_id:'e1',payment_status:'回収済み',payment_method:'現金',total_amount:100000,delivery_tobacco_amount:10000,party_size:2,is_settled:true},
    {id:'s2',business_date:'2026-10-01',customer_id:'c1',employee_id:'e1',payment_status:'未収',total_amount:20000,party_size:1,is_settled:false},
    {id:'s3',business_date:'2026-10-02',customer_id:'c2',employee_id:'e2',payment_status:'回収済み',payment_method:'カード',total_amount:60000,party_size:3,is_settled:false}
   ];
   expenses=[{id:'x1',expense_date:'2026-10-02',amount:5000,category:'備品・消耗品'}];
   $('appLoading').classList.add('hidden');$('authScreen').classList.add('hidden');$('protectedApp').classList.remove('hidden');goToPage('analytics','売上分析');
   $('analyticsStartDate').value='2026-10-01';$('analyticsEndDate').value='2026-10-07';renderAnalytics();
   const root=$('analyticsDetailRoot'),text=root.textContent;
   return{ text,stats:[...root.querySelectorAll('.analytics-detail-stat strong')].map(node=>node.textContent),dailyRows:root.querySelectorAll('details[open] tbody tr').length,details:root.querySelectorAll('details').length,overflow:document.documentElement.scrollWidth<=innerWidth };
  });
  assert.deepEqual(result.stats,['2件','5名','¥80,000','¥150,000','¥10,000','¥60,000','¥20,000','¥5,000']);
  assert.equal(result.dailyRows,2);assert.equal(result.details,4);assert.match(result.text,/オーナー/);assert.match(result.text,/店長/);assert.match(result.text,/田中さん/);assert.match(result.text,/佐藤さん/);assert.ok(result.overflow);assert.deepEqual(errors,[]);
  fs.mkdirSync(path.resolve(__dirname,'../../.validation'),{recursive:true});await page.screenshot({path:path.resolve(__dirname,'../../.validation/analytics-details-mobile.png'),fullPage:true});
  console.log('PASS: detailed analytics totals, daily/weekday/employee/customer tables and mobile width.');
 }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exit(1)});