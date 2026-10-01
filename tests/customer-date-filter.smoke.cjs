const assert=require('node:assert/strict');
const path=require('node:path');
const {chromium}=require('C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});try{
 const page=await browser.newPage({viewport:{width:390,height:844}});
 await page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',r=>r.fulfill({contentType:'application/javascript',body:'window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};'}));
 await page.route('https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js',r=>r.fulfill({contentType:'application/javascript',body:'window.Chart=class{constructor(){}destroy(){}update(){}};'}));
 await page.goto('file:///'+path.resolve(__dirname,'../index.html').replaceAll('\\','/'));
 const result=await page.evaluate(async()=>{
  currentAuthUser={id:'owner'};currentStoreMember={user_id:'owner',role:'owner'};
  const month=dateString().slice(0,7),firstDate=`${month}-01`,secondDate=`${month}-02`;
  customers=[{id:'c1',name:'一日来店'},{id:'c2',name:'二日来店'}];employees=[];
  sales=[{id:'s1',customer_id:'c1',business_date:firstDate,record_type:'sale',total_amount:1},{id:'s2',customer_id:'c2',business_date:secondDate,record_type:'sale',total_amount:1}];
  saleCompanions=[];bottles=[];renderCustomerList();
  const initial=$('customerList').textContent;
  renderCustomerDetail('c1');const controlsHiddenInDetail=$('customerListControls').classList.contains('hidden');
  renderPage('home');renderPage('customers');const controlsRestored=!$('customerListControls').classList.contains('hidden');
  renderCustomerDetail('c1');openCustomerEditor('c1');appConfirm=async()=>true;
  db.from=()=>({update:()=>({eq:()=>({select:async()=>({data:[{id:'c1'}],error:null})})})});loadAll=async()=>{};
  await $('deleteCustomerBtn').onclick();
  const controlsRestoredAfterDelete=!$('customerListControls').classList.contains('hidden')&&!$('customerList').classList.contains('hidden');
  customerVisitDatePicker.openPicker();document.querySelector(`[data-customer-calendar-date="${firstDate}"]`).click();$('customerVisitDateModal').click();
  const cancelled={value:$('customerVisitDate').value,list:$('customerList').textContent};
  customerVisitDatePicker.openPicker();document.querySelector(`[data-customer-calendar-date="${secondDate}"]`).click();$('confirmCustomerVisitDate').click();
  return{initial,firstDate,secondDate,cancelled,committed:{value:$('customerVisitDate').value,list:$('customerList').textContent,label:$('openCustomerVisitDate').textContent},nativeHidden:$('customerVisitDate').classList.contains('hidden'),controlsHiddenInDetail,controlsRestored,controlsRestoredAfterDelete,readingLicenseRemoved:!document.body.textContent.includes('読み検索の辞書・ライセンス'),width:document.documentElement.scrollWidth}
 });
 assert.match(result.initial,/一日来店/);assert.match(result.initial,/二日来店/);assert.ok(result.controlsHiddenInDetail);assert.ok(result.controlsRestored);assert.ok(result.controlsRestoredAfterDelete);assert.ok(result.readingLicenseRemoved);assert.equal(result.cancelled.value,'');assert.match(result.cancelled.list,/一日来店/);assert.match(result.cancelled.list,/二日来店/);assert.equal(result.committed.value,result.secondDate);assert.doesNotMatch(result.committed.list,/一日来店/);assert.match(result.committed.list,/二日来店/);assert.match(result.committed.label,new RegExp(result.secondDate.replaceAll('-','\\/')));assert.ok(result.nativeHidden);assert.ok(result.width<=390);console.log('PASS: customer controls restore after back and deletion, license notice removal, explicit date commit, filtering and mobile width.');
}finally{await browser.close()}})().catch(error=>{console.error(error);process.exit(1)});

