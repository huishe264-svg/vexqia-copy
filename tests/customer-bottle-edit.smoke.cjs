const assert = require("node:assert/strict");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const root = path.resolve(__dirname, "..");
  const browser = await chromium.launch({ headless: true, executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe" });
  const page = await browser.newPage();
  await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2", route => route.fulfill({
    contentType: "application/javascript",
    body: `window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};`,
  }));
  await page.route("https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js", route => route.fulfill({
    contentType: "application/javascript",
    body: `window.Chart=class{constructor(){}destroy(){}update(){}};`,
  }));
  await page.goto(`file:///${path.join(root, "index.html").replaceAll("\\", "/")}`);

  const result = await page.evaluate(async () => {
    storeId = "store-1";
    currentStoreMember = { role: "owner" };
    customers = [{ id: "customer-1", name: "顧客A", is_active: true }];
    employees = [];
    bottles = [];
    bottleBrands = [];
    let insertedBrand = null;
    let insertedBottle = null;
    loadAll = async () => {};
    renderCustomerDetail = () => {};
    db.from = table => {
      if (table === "customers") return { update: () => ({ eq: async () => ({ error: null }) }) };
      if (table === "bottle_brands") return {
        insert: values => ({ select: () => ({ single: async () => {
          insertedBrand = { id: "brand-new", ...values };
          return { data: insertedBrand, error: null };
        } }) }),
      };
      if (table === "bottles") return {
        insert: async values => {
          insertedBottle = values;
          return { error: null };
        },
      };
      throw new Error(`unexpected table ${table}`);
    };

    openCustomerEditor("customer-1");
    document.getElementById("customerAddBottleName").value = "新しい銘柄";
    document.getElementById("customerAddBottleNumber").value = "12";
    await document.getElementById("saveCustomerEdit").onclick();

    return {
      hintVisible: document.getElementById("customerEditBody").textContent.includes("ボトル銘柄管理へ自動登録"),
      brandCreated: insertedBrand?.name === "新しい銘柄",
      bottleLinked: insertedBottle?.brand_id === "brand-new" && insertedBottle?.name === "新しい銘柄" && insertedBottle?.customer_id === "customer-1",
    };
  });

  assert.deepEqual(result, { hintVisible: true, brandCreated: true, bottleLinked: true });
  await browser.close();
  console.log("customer bottle edit smoke test passed");
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
