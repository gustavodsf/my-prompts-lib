#!/usr/bin/env node
// Generates codemap.md: modules, files and exported signatures, no bodies.
// Usage: node codemap.mjs <repo-root> [srcGlobDir...] > codemap.md
// Uses the project's own `typescript` package (resolved from <repo-root>).
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

// --out FILE writes UTF-8 directly (Windows PowerShell 5.1 `>` would write UTF-16).
const argv = process.argv.slice(2);
let outFile = null;
const outAt = argv.indexOf('--out');
if (outAt >= 0) { outFile = argv[outAt + 1]; argv.splice(outAt, 2); if (!outFile) { console.error('--out needs a file'); process.exit(1); } }
const root = path.resolve(argv[0] || '.');
const dirs = argv.slice(1);
let ts;
try { ts = createRequire(path.join(root, 'package.json'))('typescript'); }
catch { ts = null; }
if (!ts || typeof ts.createSourceFile !== 'function') {
  // TypeScript 7 (native) has no JS compiler API; use a 5.x copy outside the project.
  console.error('codemap.mjs needs the TypeScript 5.x compiler API (TypeScript 7 has none). Install it in the project (npm i -D typescript@5) or next to this script, or use: npx repomix --compress');
  try { ts = createRequire(import.meta.url)('typescript'); } catch {}
  if (!ts || typeof ts.createSourceFile !== 'function') process.exit(1);
}

const skip = /(^|\/)(node_modules|dist|build|coverage|generated|\.next)(\/|$)|\.d\.ts$|\.(test|spec)\.[jt]sx?$/;
let files;
try { files = execFileSync('git', ['-C', root, 'ls-files', ...dirs], { encoding: 'utf8' }).split('\n'); }
catch { console.error('not a git repository: ' + root); process.exit(1); }
files = files.filter(f => /\.(ts|tsx|js|jsx|mjs)$/.test(f) && !skip.test(f)).sort();

const clean = s => s.replace(/\s+/g, ' ').trim();
const sig = (node, sf) => {
  // text of the node up to (not including) its body
  const body = node.body;
  const end = body ? body.getStart(sf) : node.getEnd();
  return clean(sf.text.slice(node.getStart(sf), end)).replace(/[{=]\s*$/, '').trim();
};
const exported = n => (ts.getCombinedModifierFlags(n) & ts.ModifierFlags.Export) !== 0;
const isPublic = m => !(ts.getCombinedModifierFlags(m) & (ts.ModifierFlags.Private | ts.ModifierFlags.Protected)) && !(m.name && ts.isPrivateIdentifier(m.name));

const commit = (() => { try { return execFileSync('git', ['-C', root, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return '?'; } })();
const out = [`# Code map (generated — do not edit)`, ``, `Commit: ${commit}. Regenerate with codemap.mjs. Grep, do not read whole.`, ``];
let module = null;
for (const f of files) {
  const sf = ts.createSourceFile(f, fs.readFileSync(path.join(root, f), 'utf8'), ts.ScriptTarget.Latest, true);
  const lines = [];
  for (const st of sf.statements) {
    if (!exported(st) && !ts.isExportAssignment(st)) continue;
    if (ts.isClassDeclaration(st) || ts.isInterfaceDeclaration(st)) {
      const head = clean(sf.text.slice(st.getStart(sf), st.members.pos)).replace(/\{\s*$/, '').trim();
      lines.push(`- ${head}`);
      for (const m of st.members) {
        if (!isPublic(m) || ts.isClassStaticBlockDeclaration?.(m)) continue;
        if (ts.isMethodDeclaration(m) || ts.isConstructorDeclaration(m) || ts.isMethodSignature(m) || ts.isGetAccessor(m) || ts.isSetAccessor(m))
          lines.push(`  - ${sig(m, sf)}`);
        else if (ts.isPropertyDeclaration(m) || ts.isPropertySignature(m))
          lines.push(`  - ${clean(sf.text.slice(m.getStart(sf), m.initializer ? m.initializer.pos : m.getEnd())).replace(/[=;]\s*$/, '').trim()}`);
      }
    } else if (ts.isFunctionDeclaration(st)) {
      lines.push(`- ${sig(st, sf)}`);
    } else if (ts.isVariableStatement(st)) {
      for (const d of st.declarationList.declarations) {
        const fn = d.initializer && (ts.isArrowFunction(d.initializer) || ts.isFunctionExpression(d.initializer)) ? d.initializer : null;
        const head = fn ? `${d.name.getText(sf)} = ${sig(fn, sf).replace(/=>\s*$/, '')}` : clean(d.name.getText(sf) + (d.type ? ': ' + d.type.getText(sf) : ''));
        lines.push(`- const ${head}`);
      }
    } else if (ts.isTypeAliasDeclaration(st) || ts.isEnumDeclaration(st)) {
      lines.push(`- ${clean(st.getText(sf).split('=')[0].split('{')[0])}`);
    } else if (ts.isExportDeclaration(st) || ts.isExportAssignment(st)) {
      lines.push(`- ${clean(st.getText(sf)).slice(0, 160)}`);
    }
  }
  if (!lines.length) continue;
  const mod = path.dirname(f);
  if (mod !== module) { out.push(``, `## ${mod}`); module = mod; }
  out.push(``, `### ${f}`, ...lines);
}
if (outFile) fs.writeFileSync(outFile, out.join('\n') + '\n', 'utf8');
else process.stdout.write(out.join('\n') + '\n');
