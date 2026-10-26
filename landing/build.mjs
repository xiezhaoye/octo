import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,mkdirSync,rmSync,cpSync,existsSync} from 'node:fs';
import {join} from 'node:path';
const root=import.meta.dirname,dist=join(root,'dist');
let html=readFileSync(join(root,'index.html'),'utf8');
const required=['assets/logo.png','assets/octo-workspace.jpg','assets/octo-list.jpg','assets/octo-icons.jpg'];
for(const asset of required)if(!existsSync(join(root,asset)))throw Error(`Missing asset: ${asset}`);
const downloads=[...html.matchAll(/href="([^"]+\.zip)"/g)].map(m=>m[1]);
if(downloads.length<2||downloads.some(url=>url!=='https://octo-dl.xiezhaoye.site/Octo-0.4.2-macos-arm64.zip'))throw Error('Download links must use the versioned Octo R2 domain');
if(!html.includes('https://github.com/xiezhaoye/octo')||!html.includes('尚未经过 Apple 公证'))throw Error('Missing project or notarization disclosure');
rmSync(dist,{recursive:true,force:true});mkdirSync(dist,{recursive:true});
for(const path of ['index.html','style.css','site.js','404.html','robots.txt','sitemap.xml','_headers','assets'])cpSync(join(root,path),join(dist,path),{recursive:true});
for(const file of ['style.css','site.js']){
  const data=readFileSync(join(root,file));const hash=createHash('sha256').update(data).digest('hex').slice(0,12);
  const [stem,ext]=file.split('.');const versioned=`${stem}.${hash}.${ext}`;
  writeFileSync(join(dist,versioned),data);html=html.replace(`"${file}"`,`"${versioned}"`);
}
writeFileSync(join(dist,'index.html'),html);
console.log('Built Octo landing: assets, download links, disclosure, content hashes verified.');
