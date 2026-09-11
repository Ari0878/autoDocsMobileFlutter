const { chromium } = require('C:/Users/DELL/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{
const browser=await chromium.launch({channel:'msedge',headless:true});
const page=await browser.newPage();
await page.route('https://**/*',route=>route.abort());
await page.goto('file:///'+process.cwd().replaceAll('\\','/')+'/tmp/pdfs/muestra.html');
await page.pdf({path:'tmp/pdfs/html-preview.pdf',format:'A4',printBackground:true,preferCSSPageSize:true});
await browser.close();
})();
