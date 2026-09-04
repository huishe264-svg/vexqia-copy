const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const {chromium}=require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");
(async()=>{const root=path.resolve(__dirname,".."),html=fs.readFileSync(path.join(root,"index.html"),"utf8"),js=fs.readFileSync(path.join(root,"owner-finance.js"),"utf8"),sql=fs.readFileSync(path.join(root,"supabase/migrations/20260904120000_owner_finance_and_receipts.sql"),"utf8");
assert.match(html,/data-owner-only data-page="finance"/);assert.match(sql,/storage\.buckets/);assert.match(sql,/public\.is_store_owner\(store_id\)/);assert.match(sql,/get_owner_monthly_finance/);assert.match(sql,/sale_payment_events/);assert.match(js,/現金払いだけレジ金から差し引きます/);assert.match(js,/経費CSVを出力/);
const browser=await chromium.launch({headless:true,executablePath:"C:/Program Files/Google/Chrome/Application/chrome.exe"}),page=await browser.newPage({viewport:{width:390,height:844}});
await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2",r=>r.fulfill({contentType:"application/javascript",body:`window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};`}));
await page.route("https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js",r=>r.fulfill({contentType:"application/javascript",body:"window.Chart=class{destroy(){}update(){}}"}));
await page.goto(`file:///${path.join(root,"index.html").replaceAll("\\","/")}`);
const result=await page.evaluate(async()=>{currentAuthUser={id:"owner"};currentStoreMember={user_id:"owner",role:"owner"};storeId="store";platformAdminMode=false;
const query=data=>{const q={select(){return q},eq(){return q},is(){return q},order(){return q},limit(){return q},gte(){return q},lte(){return q},range(){return q},then(resolve){resolve({data,error:null})}};return q};
db.from=table=>query(table==="expenses"?[{id:"e1",store_id:"store",expense_date:dateString(),amount:3000,vendor:"酒販店",category:"酒類",payment_method:"現金",memo:"追加仕入",created_at:new Date().toISOString()}]:[]);
db.rpc=async name=>name==="get_owner_monthly_finance"?{data:{total_sales:200000,cash_sales:100000,card_sales:100000,other_sales:0,unpaid_amount:20000,unpaid_count:1,collected_unpaid:10000,expense_total:3000,supply_expense:3000,monthly_goal:300000,category_expenses:[{category:"酒類",amount:3000}]},error:null}:{data:null,error:null};
applyRoleNavigation();goToPage("finance","経費・収支");await new Promise(r=>setTimeout(r,120));const text=document.getElementById("ownerFinanceRoot").textContent;return{ownerPage:text.includes("利益の参考値")&&text.includes("月次収支"),csvTab:Boolean(document.querySelector('[data-ft="export"]')),mobile:document.documentElement.scrollWidth<=390,ownerMenu:!document.querySelector('.drawer-link[data-page="finance"]').classList.contains("hidden")}});
assert.deepEqual(result,{ownerPage:true,csvTab:true,mobile:true,ownerMenu:true});
if(process.env.VEXQIA_CAPTURE_PATH){
  await page.evaluate(()=>{currentAuthUser={id:"owner"};currentStoreMember={user_id:"owner",role:"owner"};storeId="store";document.getElementById("authScreen").classList.add("hidden");document.getElementById("protectedApp").classList.remove("hidden");applyRoleNavigation();goToPage("finance","経費・収支")});
  await page.waitForTimeout(120);
  await page.screenshot({path:process.env.VEXQIA_CAPTURE_PATH,fullPage:true});
}
console.log("Owner finance smoke test passed.");await browser.close()})().catch(e=>{console.error(e);process.exit(1)});
