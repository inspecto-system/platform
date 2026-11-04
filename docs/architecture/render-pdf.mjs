// Renders the built HTML into an A4 PDF with running header, page numbers
// and page numbers in the table of contents (two passes; page lookup via pdftotext).
// Usage: node render-pdf.mjs <input.html> <output.pdf>
import puppeteer from 'puppeteer';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const [input, output] = process.argv.slice(2);
if (!input || !output) {
  console.error('Usage: node render-pdf.mjs <input.html> <output.pdf>');
  process.exit(2);
}

const FONT = 'DejaVu Sans,Arial,sans-serif';
const PDF_OPTIONS = {
  format: 'A4',
  printBackground: true,
  displayHeaderFooter: true,
  headerTemplate: `<div style="font-size:7.5pt;color:#5b6470;width:100%;padding:0 18mm 0 22mm;font-family:${FONT};display:flex;justify-content:space-between"><span>Inspecto · Архитектура информационной системы</span><span>Версия 0.2</span></div>`,
  footerTemplate: `<div style="font-size:8pt;color:#5b6470;width:100%;text-align:center;font-family:${FONT}">Стр. <span class="pageNumber"></span> из <span class="totalPages"></span></div>`,
  margin: { top: '22mm', bottom: '20mm', left: '22mm', right: '18mm' },
};

// Whitespace and hyphens are dropped: long headings wrap (and get dehyphenated) differently in the TOC and the body.
const normalize = (text) => text.replace(/[\s\u00ad-]+/g, '');
const key = (text) => normalize(text).slice(0, 28);

function pageTexts(pdfPath) {
  const text = execFileSync('pdftotext', [pdfPath, '-'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  return text.split('\f').map(normalize);
}

const browser = await puppeteer.launch({
  executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || undefined,
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
});
const workDir = mkdtempSync(path.join(tmpdir(), 'inspecto-pdf-'));
try {
  const page = await browser.newPage();
  await page.goto(pathToFileURL(path.resolve(input)).href, { waitUntil: 'networkidle0' });

  // Pass 1: paginate without TOC page numbers.
  const draft = path.join(workDir, 'draft.pdf');
  await page.pdf({ ...PDF_OPTIONS, path: draft });
  const pages = pageTexts(draft);

  const entries = await page.$$eval('nav#TOC a', (links) =>
    links.map((a) => ({ href: a.getAttribute('href'), text: a.textContent })),
  );
  // TOC pages are the pages that contain many TOC entry titles; headings are searched after them.
  const tocPages = pages
    .map((t, i) => [i, entries.filter((e) => t.includes(key(e.text))).length])
    .filter(([, hits]) => hits >= 5)
    .map(([i]) => i);
  const numbers = {};
  let cursor = Math.max(...tocPages) + 1;
  for (const entry of entries) {
    const needle = key(entry.text);
    for (let i = cursor; i < pages.length; i++) {
      if (pages[i].includes(needle)) {
        numbers[entry.href] = i + 1;
        cursor = i;
        break;
      }
    }
    if (!numbers[entry.href]) throw new Error(`Heading not found in PDF: ${needle}`);
  }

  // Pass 2: inject page numbers into the TOC and render the final PDF.
  await page.evaluate((map) => {
    for (const a of document.querySelectorAll('nav#TOC a')) {
      const span = document.createElement('span');
      span.className = 'toc-page';
      span.textContent = map[a.getAttribute('href')];
      a.appendChild(span);
    }
  }, numbers);
  await page.pdf({ ...PDF_OPTIONS, path: output });

  const final = pageTexts(output);
  if (final.length !== pages.length) {
    throw new Error(`Page count changed between passes (${pages.length} -> ${final.length})`);
  }
  console.log(`PDF: ${final.length - 1} pages, ${entries.length} TOC entries`);
} finally {
  await browser.close();
  rmSync(workDir, { recursive: true, force: true });
}
