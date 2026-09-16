const assert=require('node:assert/strict');
const path=require('node:path');
const {chromium}=require('C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
 try {
  const page=await browser.newPage();
  await page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',r=>r.fulfill({contentType:'application/javascript',body:'window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};'}));
  await page.route('https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js',r=>r.fulfill({contentType:'application/javascript',body:'window.Chart=class{constructor(){}destroy(){}update(){}};'}));
  await page.goto('file:///'+path.resolve(__dirname,'../index.html').replaceAll('\\','/'));
  const result=await page.evaluate(async()=>{
   currentAuthUser={id:'owner'};currentStoreMember={user_id:'owner',role:'owner'};storeId='test-store';storeMembers=[currentStoreMember];storeOperatingSettings={demo_configuration_enabled:true,payment_methods:['現金','カード']};
   customers=[{id:'c',name:'テスト顧客'}];employees=[{id:'e',name:'担当'}];
   sales=[{id:'old',store_id:storeId,business_date:'2026-08-30',customer_id:'c',employee_id:'e',payment_status:'未収',payment_method:null,party_size:1,total_amount:30000,is_settled:false}];
   db.from=()=>({select:()=>({eq:()=>({eq:()=>({order:()=>({limit:async()=>({data:[]})})})})})});
   let request;db.rpc=async(name,args)=>{request={name,args};return {data:{id:'receipt'},error:null}};
   loadAll=async()=>{};showStatus=()=>{};
   applyDemoOperatingSettings();openSaleEditor('old');const recoveryMethods=[...$('recoveryMethod').options].map(option=>option.value);const normalMethods=[...document.querySelectorAll('[data-group="paymentMethod"]')].map(button=>button.dataset.value);$('recoveryBusinessDate').value='2026-09-14';$('recoveryMethod').value='銀行振込';await $('collectReceivableBtn').onclick();
   sales[0].payment_status='回収済み';sales[0].recognized_via_sale_id='receipt';
   sales.push({id:'receipt',business_date:'2026-09-14',customer_id:'c',employee_id:'e',payment_status:'回収済み',payment_method:'銀行振込',party_size:0,total_amount:30000,delivery_tobacco_amount:0,record_type:'receivable_payment',is_settled:false});
   renderSalesDay('2026-09-14');const dayText=$('salesDayDetail').textContent;
   openSaleEditor('receipt');
   return {request,dayText,recoveryMethods,normalMethods,editMethod:$('editSaleMethod').value,visits:directVisitCount('c'),total:totalSales(recoveredSales(sales)),cash:totalSales(recoveredSales(sales).filter(s=>s.payment_method==='現金'))};
  });
  assert.equal(result.request.name,'collect_receivable_payment');assert.equal(result.request.args.target_business_date,'2026-09-14');assert.equal(result.request.args.target_payment_method,'銀行振込');assert.equal(result.request.args.target_received_amount,30000);
  assert.deepEqual(result.normalMethods,['現金','カード']);assert.ok(result.recoveryMethods.includes('銀行振込'));assert.equal(result.editMethod,'銀行振込');assert.equal(result.visits,1);assert.equal(result.total,30000);assert.equal(result.cash,0);assert.match(result.dayText,/銀行振込/);assert.match(result.dayText,/レジ金への加算なし/);
  console.log('Bank transfer collection: selected date, edit retention, revenue, cash exclusion and visit count passed.');
 } finally {await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
