const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const root=path.resolve(__dirname,".."),sql=fs.readFileSync(path.join(root,"supabase/migrations/20260917100000_settlement_reopen_permissions.sql"),"utf8"),js=fs.readFileSync(path.join(root,"settlement-corrections.js"),"utf8");
  assert.match(sql,/manager_settled_sale_edit boolean not null default false/);
  assert.match(sql,/current_amount=register_after/);
  assert.match(sql,/is_settled=false, settled_at=null, settlement_id=null/);
  assert.match(sql,/delete from public\.business_day_closures/);
  assert.match(sql,/delete from public\.daily_settlements/);
  assert.match(sql,/'settlement_reopen'/);
  assert.match(js,/同じ精算/);
  assert.match(js,/distance>=75/);

  const browser=await chromium.launch({headless:true,executablePath:"C:/Program Files/Google/Chrome/Application/chrome.exe"});
  try{
    const page=await browser.newPage({viewport:{width:390,height:844},hasTouch:true});
    await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2",route=>route.fulfill({contentType:"application/javascript",body:"window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};"}));
    await page.route("https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js",route=>route.fulfill({contentType:"application/javascript",body:"window.Chart=class{constructor(){}destroy(){}update(){}};"}));
    await page.goto("file:///"+path.join(root,"index.html").replaceAll("\\","/"));
    const result=await page.evaluate(async()=>{
      currentAuthUser={id:"owner"};currentStoreMember={user_id:"owner",role:"owner"};platformAdminMode=false;storeOperatingSettings={manager_settled_sale_edit:false};
      renderSettlementEditPermission();
      const ownerCard=Boolean(document.getElementById("settlementEditPermission")),ownerPermission=canReopenSettledSale();
      currentStoreMember={user_id:"manager",role:"manager"};
      const managerDenied=canReopenSettledSale();storeOperatingSettings.manager_settled_sale_edit=true;const managerAllowed=canReopenSettledSale();
      let refreshes=0;loadAll=async()=>{refreshes++};renderPage=()=>{};
      const touch=(type,y)=>{const event=new Event(type,{bubbles:true});Object.defineProperty(event,"touches",{value:type==="touchend"?[]:[{clientY:y}]});document.body.dispatchEvent(event)};
      touch("touchstart",10);touch("touchmove",100);touch("touchend",100);await new Promise(resolve=>setTimeout(resolve,20));
      return{ownerCard,ownerPermission,managerDenied,managerAllowed,refreshes,indicator:Boolean(document.getElementById("pullRefreshIndicator"))};
    });
    assert.deepEqual(result,{ownerCard:true,ownerPermission:true,managerDenied:false,managerAllowed:true,refreshes:1,indicator:true});
    console.log("Settlement reopen permission and pull refresh test passed.");
  }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exit(1)});
