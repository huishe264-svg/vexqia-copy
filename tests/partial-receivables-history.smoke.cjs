const assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs');
const {chromium}=require('C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844},hasTouch:true});const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.route('https://**/*',route=>route.fulfill({contentType:'application/javascript',body:route.request().url().includes('@supabase')?'window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};':'window.Chart=class{constructor(){}destroy(){}update(){}};'}));
  await page.goto('file:///'+path.resolve(__dirname,'../index.html').replaceAll('\\','/'));
  await page.evaluate(()=>{
   currentAuthUser={id:'owner'};currentStoreMember={user_id:'owner',role:'owner'};storeMembers=[currentStoreMember];storeId='test';platformAdminMode=false;
   storeOperatingSettings={expense_management_mode:'simple',payment_methods:['現金','カード']};
   customers=[{id:'customer',name:'テスト顧客',is_active:true}];employees=[{id:'employee',name:'担当'}];
   sales=[{id:'debt',business_date:'2026-09-28',customer_id:'customer',employee_id:'employee',payment_status:'未収',total_amount:110000,original_total_amount:110000,party_size:1},{id:'today',business_date:'2026-09-29',customer_id:'customer',employee_id:'employee',payment_status:'回収済み',payment_method:'カード',total_amount:15000,delivery_tobacco_amount:1000,is_settled:false,party_size:1}];
   expenses=[];cashRegister={base_amount:30000,current_amount:45000};cashRegisterHistory=[];settlements=[];businessDayClosures=[];
   db.from=table=>{let from=0,to=49;const q={select(){return q},eq(){return q},in(){return q},is(){return q},order(){return q},limit(){return q},range(a,b){from=a;to=b;return q},then(resolve){resolve({data:table==='sale_audit_log'?[]:Array.from({length:Math.max(0,Math.min(to+1,123)-from)},(_,i)=>({id:String(from+i),created_at:'2026-09-29T10:00:00Z',created_by:'owner',action:'settlement',amount_delta:1000,balance_after:30000,expense_date:'2026-09-29',amount:1000})),error:null})}};return q};
   $('appLoading').classList.add('hidden');$('authScreen').classList.add('hidden');$('protectedApp').classList.remove('hidden');goToPage('sales');
  });
  assert.equal(await page.locator('.cash-register-card > .cash-expense-entry').count(),1);
  assert.equal(await page.locator('#cashRegisterSection > .expense-entry-card').count(),0);
  assert.match(await page.locator('#toggleSimpleExpenseEntry').textContent(),/その他経費を登録/);
  assert.equal(await page.locator('#simpleExpenseEntryFields').isVisible(),false);
  await page.locator('#toggleSimpleExpenseEntry').click();await page.locator('.simple-expense-amount').fill('1200');
  await page.locator('#toggleSimpleExpenseEntry').click();await page.locator('#toggleSimpleExpenseEntry').click();assert.equal(await page.locator('.simple-expense-amount').inputValue(),'1200');await page.locator('#toggleSimpleExpenseEntry').click();
  const dateText=await page.locator('[data-sales-date="2026-09-29"]').textContent();assert.match(dateText,/火/);assert.match(dateText,/14,000/);assert.match(dateText,/未精算/);
  for(const kind of ['cash','expense']){
   await page.locator(`[data-full-history="${kind}"]`).click();await page.waitForFunction(()=>document.querySelector('.full-finance-history')?.children.length===50);
   await page.locator('.load-finance-history').click();await page.waitForFunction(()=>document.querySelector('.full-finance-history').children.length===100);
   await page.locator('.load-finance-history').click();await page.waitForFunction(()=>document.querySelector('.full-finance-history').children.length===123);assert.equal(await page.locator('.load-finance-history').isVisible(),false);
   await page.locator('#fullFinanceHistoryModal .close-btn').click();
  }
  for(const width of [360,390,430]){await page.setViewportSize({width,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true)}
  fs.mkdirSync(path.resolve(__dirname,'../../.validation'),{recursive:true});await page.screenshot({path:path.resolve(__dirname,'../../.validation/settlement-mobile.png'),fullPage:true});
  await page.evaluate(()=>{goToPage('input');$('customerId').value='customer';selectedPaymentStatus='回収済み';selectedPaymentMethod='カード';$('totalAmount').value='15000';renderReceivableCombine()});
  await page.locator('#toggleReceivableCombine').click();await page.locator('[data-receivable-id="debt"]').check();await page.locator('[data-receivable-amount="debt"]').fill('10000');
  assert.match(await page.locator('[data-receivable-remaining="debt"]').textContent(),/100,000/);assert.match(await page.locator('#receivableAllocationSummary').textContent(),/5,000/);
  assert.deepEqual(await page.evaluate(()=>selectedReceivableAllocations()),[{sale_id:'debt',amount:10000}]);
  await page.screenshot({path:path.resolve(__dirname,'../../.validation/receivable-mobile.png'),fullPage:true});
  const partial=await page.evaluate(()=>{
   sales[0].total_amount=100000;sales[0].receivable_remaining_amount=100000;saleReceivableLinks=[{receivable_sale_id:'debt',payment_sale_id:'today',original_receivable_amount:110000,allocated_amount:10000}];openSaleEditor('debt');
   return {recovery:!!$('collectReceivableBtn'),remaining:$('recoveryAmount').value,note:$('saleEditBody').textContent};
  });assert.equal(partial.recovery,true);assert.equal(partial.remaining,'100000');assert.match(partial.note,/110,000/);assert.match(partial.note,/100,000/);
  await page.evaluate(()=>{closeModal('saleEditModal');$('customerId').value='customer';selectedReceivableIds=new Set(['debt']);selectedReceivableAmounts=new Map([['debt',10000]]);$('totalAmount').value='15000';selectedPaymentStatus='回収済み';selectedPaymentMethod='カード';validateSaleWithBrands=()=>true;resolveCompanionIds=async()=>[];loadAll=async()=>{};showSaleSuccess=()=>{};showStatus=()=>{};window.savedRequests=[];db.rpc=async(name,args)=>{window.savedRequests.push({name,args});return {data:{duplicate:false}}}});
  await page.evaluate(()=>$('saveBtn').onclick());
  const saved=await page.evaluate(()=>window.savedRequests);assert.equal(saved.length,1);assert.equal(saved[0].name,'create_reliable_sale_with_allocations');assert.deepEqual(saved[0].args.target_receivable_allocations,[{sale_id:'debt',amount:10000}]);assert.equal(saved[0].args.target_total_amount,15000);
  assert.deepEqual(errors,[]);console.log('PASS mobile collapse / all 123 history rows / weekday / unsettled gross / partial repayment controls');
 }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exit(1)});

