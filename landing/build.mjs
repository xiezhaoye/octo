import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,mkdirSync,rmSync,cpSync,existsSync} from 'node:fs';
import {join} from 'node:path';
const root=import.meta.dirname,dist=join(root,'dist');
const [version,build]=readFileSync(join(root,'../VERSION'),'utf8').trim().split(/\r?\n/);
if(!/^\d+\.\d+\.\d+$/.test(version)||!/^\d+$/.test(build))throw Error('Invalid VERSION');
let html=readFileSync(join(root,'index.html'),'utf8').replaceAll('{{VERSION}}',version);
let script=readFileSync(join(root,'site.js'),'utf8');
const required=['assets/logo.png','assets/octo-workspace.jpg','assets/octo-list.jpg','assets/octo-icons.jpg','assets/octo-document-preview.jpg','assets/octo-json-preview.jpg','assets/octo-image-browsing.jpg','assets/octo-image-overview.jpg'];
for(const asset of required)if(!existsSync(join(root,asset)))throw Error(`Missing asset: ${asset}`);
const downloads=[...html.matchAll(/href="([^"]+\.zip)"/g)].map(m=>m[1]);
if(downloads.length<2||downloads.some(url=>url!==`https://octo-dl.xiezhaoye.site/Octo-${version}-macos-arm64.zip`))throw Error('Download links must use the current versioned Octo R2 domain');
if(!html.includes('https://github.com/xiezhaoye/octo')||!html.includes('尚未经过 Apple 公证')||!html.includes('版本更新内容'))throw Error('Missing release content');
if(/\{\{[^}]+\}\}/.test(html))throw Error('Unresolved template');
rmSync(dist,{recursive:true,force:true});mkdirSync(dist,{recursive:true});
for(const path of ['404.html','robots.txt','sitemap.xml','_headers','assets'])cpSync(join(root,path),join(dist,path),{recursive:true});
// Fresh image URLs prevent a browser's previous screenshot cache from hiding this update.
for(const asset of required){
 const data=readFileSync(join(root,asset)),hash=createHash('sha256').update(data).digest('hex').slice(0,12);
 const versioned=asset.replace(/(\.[^.]+)$/,`.${hash}$1`);
 writeFileSync(join(dist,versioned),data);html=html.replaceAll(asset,versioned);script=script.replaceAll(asset,versioned);
}
for(const [file,data] of [['style.css',readFileSync(join(root,'style.css'))],['site.js',Buffer.from(script)]]){
 const hash=createHash('sha256').update(data).digest('hex').slice(0,12);
 const [stem,ext]=file.split('.'),versioned=`${stem}.${hash}.${ext}`;
 writeFileSync(join(dist,versioned),data);html=html.replace(`"${file}"`,`"${versioned}"`);
}
writeFileSync(join(dist,'index.html'),html);
console.log(`Built Octo ${version} (${build}): screenshots, download links, disclosure, release notes and content hashes verified.`);
