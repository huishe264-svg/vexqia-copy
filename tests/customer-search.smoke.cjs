const assert=require('node:assert/strict');
const path=require('node:path');
const {chromium}=require('C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
 try{
 const page=await browser.newPage({viewport:{width:390,height:844}});
 await page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',r=>r.fulfill({contentType:'application/javascript',body:'window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};'}));
 await page.route('https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js',r=>r.fulfill({contentType:'application/javascript',body:'window.Chart=class{constructor(){}destroy(){}update(){}};'}));
 await page.goto('file:///'+path.resolve(__dirname,'../index.html').replaceAll('\\','/'));
 const result=await page.evaluate(()=>{
 currentAuthUser={id:'owner'};currentStoreMember={user_id:'owner',role:'owner'};storeId='test';
 customers=[{id:'c1',name:'山田太郎',name_kana:'ぜったいつかわない',notes:'甘いお酒が好き\n<img src=x onerror=alert(1)>',employee_id:'e1'},{id:'c2',name:'角田',notes:null},{id:'c3',name:'山田',is_active:false},{id:'c4',name:'永井',notes:'先頭一致'},{id:'c5',name:'なんたら社長',notes:'後方一致'}];
 employees=[{id:'e1',name:'葵'}];sales=[];
 const matched=['やま','さん','やまだ','ヤマダ','たろう'].map(q=>customerNameMatches(customers[0],q));
 const ignored=!customerNameMatches(customers[0],'ぜったい');
 renderCustomerSuggestions('なが');
 const ranked=[...$('customerSuggestions').querySelectorAll('[data-pick]')].map(button=>button.dataset.pick);
 $('customerListSearch').value='なが';renderCustomerList();const listRanked=[...$('customerList').querySelectorAll('[data-customer-detail]')].map(card=>card.dataset.customerDetail);
 renderCustomerSuggestions('やま');
 const count=$('customerSuggestions').querySelectorAll('[data-pick]').length;
 $('customerSuggestions').querySelector('[data-preview]').click();
 const preview={open:$('customerQuickPreview').classList.contains('show'),notes:$('customerPreviewBody').textContent,editable:$('customerPreviewBody').querySelectorAll('input,textarea,select').length,injected:$('customerPreviewBody').querySelectorAll('img').length,selected:$('customerId').value};
 closeCustomerPreview();
 $('customerSuggestions').querySelector('[data-pick]').click();
 openNewCustomerModal();openCustomerEditor('c1');
 return {matched,ignored,count,ranked,listRanked,placeholder:$('customerListSearch').placeholder,preview,selected:$('customerId').value,readingFields:!!($('newCustomerKana')||$('editCustomerKana')),width:document.documentElement.scrollWidth};
 });
 assert.ok(result.matched.every(Boolean));assert.ok(result.ignored);assert.equal(result.count,1);assert.deepEqual(result.ranked.slice(0,2),['c4','c5']);assert.deepEqual(result.listRanked.slice(0,2),['c4','c5']);assert.match(result.placeholder,/ひらがな対応/);
 assert.ok(result.preview.open);assert.match(result.preview.notes,/甘いお酒/);assert.equal(result.preview.editable,0);assert.equal(result.preview.injected,0);assert.equal(result.preview.selected,'');assert.equal(result.selected,'c1');assert.equal(result.readingFields,false);assert.ok(result.width<=390);
 console.log('PASS: kun/on kana, compound names, ignored legacy readings, read-only escaped preview, selection and mobile width.');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
