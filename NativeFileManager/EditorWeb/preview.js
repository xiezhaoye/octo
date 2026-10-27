// Uses XMark's unified/remark/GFM pipeline and DOMPurify isolation pattern.
import {unified} from 'unified';
import remarkParse from 'remark-parse';
import remarkGfm from 'remark-gfm';
import {toHast} from 'mdast-util-to-hast';
import {toHtml} from 'hast-util-to-html';
import DOMPurify from 'dompurify';

const parser = unified().use(remarkParse).use(remarkGfm);
const frame = document.querySelector('iframe');
const style = `:root{color-scheme:light dark}body{font:15px/1.7 -apple-system,BlinkMacSystemFont,sans-serif;margin:24px;overflow-wrap:anywhere}h1,h2,h3{line-height:1.3}h1{font-size:28px}pre,code{font-family:ui-monospace,monospace;font-size:13px}pre{background:#8881;padding:14px;overflow:auto;border-radius:6px}code{background:#8881}pre code{background:none}blockquote{border-left:3px solid #8886;margin-left:0;padding-left:16px;color:GrayText}table{border-collapse:collapse;display:block;overflow:auto}td,th{border:1px solid #8885;padding:6px 12px}img{max-width:100%;height:auto}a{color:LinkText}input{pointer-events:none}summary{cursor:pointer}details{margin:4px 0}ul{padding-left:24px}.empty{color:GrayText}`;
let treeBudget = 0;
function jsonTree(value, depth = 0) {
    if (depth > 64) return document.createTextNode('…（层级过深）');
    if (value === null || typeof value !== 'object') return document.createTextNode(JSON.stringify(value));
    const root = document.createElement('div');
    for (const [key, item] of Object.entries(value)) {
        if (++treeBudget > 3000) { root.append(document.createTextNode('…（预览最多显示 3000 项，请在源码中查看其余内容）')); break; }
        const branch = item !== null && typeof item === 'object';
        const row = document.createElement(branch ? 'details' : 'div'); if (branch) row.open = depth < 2;
        const summary = document.createElement(branch ? 'summary' : 'span');
        summary.textContent = `${key}: ${item === null ? 'null' : Array.isArray(item) ? `数组 [${item.length}]` : typeof item === 'object' ? '对象' : JSON.stringify(item)}`;
        row.append(summary);
        if (item && typeof item === 'object') { const nested = jsonTree(item, depth + 1); nested.style.marginLeft = '18px'; row.append(nested); }
        root.append(row);
    }
    if (!Object.keys(value).length) root.textContent = Array.isArray(value) ? '[]' : '{}';
    return root;
}
window.renderPreview = ({content, kind, dark}) => {
    let body = '';
    if (!content.trim()) body = '<p class="empty">空白文档</p>';
    else if (kind === 'markdown') body = toHtml(toHast(parser.parse(content), {allowDangerousHtml: false}));
    else if (kind === 'html') body = content;
    else if (kind === 'json') {
        try { treeBudget = 0; const node = jsonTree(JSON.parse(content)); const wrapper = document.createElement('div'); wrapper.append(node); body = wrapper.innerHTML; }
        catch (error) { const pre = document.createElement('pre'); pre.textContent = 'JSON 语法错误：\n' + error.message; body = pre.outerHTML; }
    } else { const pre = document.createElement('pre'); pre.textContent = content; body = pre.outerHTML; }
    const clean = DOMPurify.sanitize(body, {WHOLE_DOCUMENT: true, FORBID_TAGS: ['base', 'meta', 'link', 'iframe', 'object', 'embed', 'form'], ADD_TAGS: ['details', 'summary']});
    const doc = new DOMParser().parseFromString(clean, 'text/html');
    const policy = doc.createElement('meta'); policy.httpEquiv = 'Content-Security-Policy';
    policy.content = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none'";
    doc.head.prepend(policy);
    const css = doc.createElement('style'); css.textContent = style + `body{color:${dark ? '#eee' : '#292929'};background:${dark ? '#202326' : '#fff'}}`; doc.head.append(css);
    frame.srcdoc = '<!doctype html>' + doc.documentElement.outerHTML;
};
