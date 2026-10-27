const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const root = path.resolve(__dirname, "..");
const html = fs.readFileSync(path.join(root, "index.html"), "utf8");

assert.match(html, /http-equiv="Content-Security-Policy"/);
assert.match(html, /object-src 'none'/);
assert.match(html, /base-uri 'none'/);
assert.match(html, /connect-src 'self' https:\/\/rtqvqohfbmycehxbqjyq\.supabase\.co/);
assert.match(html, /meta name="referrer" content="no-referrer"/);
assert.match(html, /\.\/vendor\/supabase-js-2\.118\.0\.min\.js/);
assert.match(html, /\.\/vendor\/chart-4\.4\.7\.min\.js/);
assert.doesNotMatch(html, /cdn\.jsdelivr\.net/);
assert.equal(fs.statSync(path.join(root, "vendor/supabase-js-2.118.0.min.js")).size > 100000, true);
assert.equal(fs.statSync(path.join(root, "vendor/chart-4.4.7.min.js")).size > 100000, true);
const sha256 = file => crypto.createHash("sha256").update(fs.readFileSync(path.join(root, file))).digest("hex").toUpperCase();
assert.equal(sha256("vendor/supabase-js-2.118.0.min.js"), "BEE24FC29228ED5A370F76A2BA1CA3C399549EDAD2FEF23453C80148856A49AF");
assert.equal(sha256("vendor/chart-4.4.7.min.js"), "206B6E8BB00FC7BBA2C7EE80CA41DB3E9E05BA7BE0AA35ABEBA9CFD5357F5D0E");

console.log("security hardening checks passed");
