const fs = require('fs');

const decode = (value) => value
  .replace(/<br\s*\/?\s*>/gi, '\n')
  .replace(/<rt>[\s\S]*?<\/rt>/gi, '')
  .replace(/<[^>]+>/g, '')
  .replace(/&nbsp;/g, ' ')
  .replace(/&#8211;/g, '-')
  .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
  .replace(/&amp;/g, '&')
  .replace(/&lt;/g, '<')
  .replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"')
  .replace(/[ \t]+/g, ' ')
  .replace(/\n\s*/g, '\n')
  .replace(/\n{2,}/g, '\n')
  .trim();

const rows = [];
for (const level of ['N5', 'N4', 'N3', 'N2', 'N1']) {
  const html = fs.readFileSync(`/private/tmp/jlpt-${level.toLowerCase()}.html`, 'utf8');
  const table = html.match(/<figure class="wp-block-flexible-table-block-table[\s\S]*?<\/table><\/figure>/)?.[0] || '';
  const tr = table.match(/<tr>[\s\S]*?<\/tr>/g) || [];
  tr.slice(1).forEach((row, index) => {
    const rawCells = [...row.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map((match) => match[1]);
    const cells = rawCells.map(decode);
    if (cells.length < 2) return;
    const grammar = cells[0];
    const meaning = (cells[1].match(/\[意思\]\s*([\s\S]*?)(?:\[规则\]|$)/)?.[1] || cells[1]).trim();
    const rule = (cells[1].match(/\[规则\]\s*([\s\S]*)$/)?.[1] || '').trim();
    const example = cells[2] || '';
    const link = rawCells[3]?.match(/<a\s+[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    const related = link ? { url: link[1].replace(/&amp;/g, '&'), label: decode(link[2]) } : null;
    if (grammar && meaning) rows.push({ id: `${level}-${index + 1}`, level, grammar, meaning, rule, example, related });
  });
}
fs.writeFileSync('data.js', `window.GRAMMAR_DATA = ${JSON.stringify(rows, null, 2)};\n`);
console.log(`Created data.js with ${rows.length} grammar entries.`);
