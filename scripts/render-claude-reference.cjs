const fs = require('node:fs/promises');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.TRUSTKEYPER_PLAYWRIGHT_MODULE || 'playwright');

async function main() {
  const directory = path.resolve(process.argv[2] || 'output/design-reference');
  const selection = new Set((process.argv[3] || '01/02,01/06,01/08,03/01,03/02').split(','));
  const manifest = JSON.parse(await fs.readFile(path.join(directory, 'manifest.json'), 'utf8'));
  const browser = await chromium.launch({ headless: true, executablePath: process.env.TRUSTKEYPER_CHROMIUM_EXECUTABLE || chromium.executablePath() });
  const context = await browser.newContext({ javaScriptEnabled: false, deviceScaleFactor: 1 });
  context.setDefaultTimeout(15000);
  await context.route(/^https?:/, route => route.abort());
  try {
    for (const section of manifest) {
      for (const board of section.boards) {
        const identifier = board.file.replace('.html', '');
        if (!selection.has(identifier) && !selection.has('all')) continue;
        const page = await context.newPage();
        await page.setViewportSize({ width: Number(board.width) || 440, height: Number(board.height) || 956 });
        console.log(`Rendering ${identifier}`);
        await page.goto(pathToFileURL(path.join(directory, board.file)).href, { waitUntil: 'domcontentloaded', timeout: 15000 });
        await page.evaluate(() => {
          const style = document.createElement('style');
          style.textContent = '* { animation: none !important; transition: none !important; }';
          document.head.appendChild(style);
        });
        const screenshot = path.join(directory, `${identifier}.png`);
        const artboard = page.locator('.scr');
        await (await artboard.count() ? artboard : page.locator('body')).screenshot({ path: screenshot });
        console.log(screenshot);
        await page.close();
      }
    }
  } finally {
    await context.close();
    await browser.close();
  }
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
