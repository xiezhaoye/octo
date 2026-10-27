// Optional rebuild only: shipped app runs the checked-in bundle fully offline.
// Usage: node EditorWeb/build.mjs /absolute/path/to/xmark
import {createRequire} from 'node:module';
import {readFile, writeFile, readdir} from 'node:fs/promises';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
const source = resolve(process.argv[2] ?? '../../xmark');
const requireXmark = createRequire(resolve(source, 'package.json'));
async function resolvePackage(name) {
    try { return requireXmark.resolve(name); } catch {}
    const store = resolve(source, 'node_modules/.pnpm');
    const prefix = name.replaceAll('/', '+') + '@';
    for (const folder of (await readdir(store)).filter(x => x.startsWith(prefix)).sort().reverse()) {
        try { return createRequire(resolve(store, folder, 'package.json')).resolve(name); } catch {}
    }
    throw new Error('Cannot resolve ' + name);
}
const {build} = await import(await resolvePackage('esbuild'));
const packages = ['unified', 'remark-parse', 'remark-gfm', 'mdast-util-to-hast', 'hast-util-to-html', 'dompurify'];
const entry = resolve(here, 'preview.js');
let code = await readFile(entry, 'utf8');
for (const name of packages) {
    const path = await resolvePackage(name);
    code = code.replaceAll(`from '${name}'`, `from '${path}'`);
}
await build({stdin:{contents:code,resolveDir:here,sourcefile:'preview.js'},bundle:true,minify:true,format:'iife',target:'safari17',outfile:resolve(here,'../Sources/DualPane/Resources/Editor/preview.js'),legalComments:'eof'});
// Collect notices from the complete dependency graph, not just direct imports.
const result = await build({stdin:{contents:code,resolveDir:here},bundle:true,write:false,metafile:true});
const roots = new Set();
for (const input of Object.keys(result.metafile.inputs)) {
    let current = dirname(resolve(input));
    while (current !== dirname(current)) {
        try { const pkg = JSON.parse(await readFile(resolve(current,'package.json'),'utf8')); if (pkg.name) { roots.add(current); break; } } catch {}
        current=dirname(current);
    }
}
const notices=[];
for (const root of [...roots].sort()) {
    const pkg=JSON.parse(await readFile(resolve(root,'package.json'),'utf8'));
    let license='';
    for (const file of ['license','LICENSE','LICENSE.md','license.md','LICENSE.txt']) { try { license=await readFile(resolve(root,file),'utf8'); break; } catch {} }
    if (!license) throw new Error('Missing license: '+pkg.name);
    notices.push(`${pkg.name} ${pkg.version}\n${license}`);
}
await writeFile(resolve(here,'../Sources/DualPane/Resources/Editor/THIRD_PARTY_NOTICES.txt'),notices.join('\n\n--------------------\n\n'));
