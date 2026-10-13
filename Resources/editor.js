'use strict';
const editor = document.getElementById('editor');
const converter = new TurndownService({headingStyle:'atx', codeBlockStyle:'fenced', bulletListMarker:'-', emDelimiter:'*'});
converter.use(turndownPluginGfm.gfm);
converter.addRule('rawInline', {filter:node=>node.nodeName==='CODE' && node.hasAttribute('data-raw-inline'),replacement:(_,node)=>node.textContent});
converter.addRule('doubleStrike', {filter:['del','s','strike'], replacement: content => '~~'+content+'~~'});
converter.addRule('taskCheckbox', {
  filter: node => node.nodeName === 'INPUT' && node.type === 'checkbox',
  replacement: (_, node) => node.checked ? '[x] ' : '[ ] '
});
converter.addRule('taskItem', {
  filter:node=>node.nodeName==='LI' && !!(node.querySelector(':scope > input[type=checkbox]') || node.querySelector(':scope > p > input[type=checkbox]')),
  replacement:content=>'- '+content.trim().replace(/^(\[[ xX]\])\s+/,'$1 ').replace(/\n/g,'\n    ')+'\n'
});
converter.addRule('safeCodeFence', {
  filter: node => node.nodeName === 'PRE' && node.firstChild && node.firstChild.nodeName === 'CODE',
  replacement: (_, node) => {
    const code=node.firstChild, text=code.textContent.replace(/\n$/, '');
    const runs=text.match(/`+/g)||[];
    const fence='`'.repeat(Math.max(3,...runs.map(s=>s.length+1)));
    const language=(code.className.match(/language-(\S+)/)||[])[1]||'';
    return '\n\n'+fence+language+'\n'+text+'\n'+fence+'\n\n';
  }
});
converter.addRule('relativeImage', {filter:'img', replacement:(_,node)=>{
  const src=node.dataset.relativeSrc || node.getAttribute('src') || '';
  const alt=(node.getAttribute('alt')||'').replace(/\[/g,'\\[').replace(/\]/g,'\\]');
  const title=node.getAttribute('title');
  return '!['+alt+']('+src.replace(/ /g,'%20')+(title?' \"'+title.replace(/\"/g,'\\\"')+'\"':'')+')';
}});
let originals = new Map(), references='', lastSent='', revision=0, pendingRemote=null;
let originalHTML='', originalMarkdown='';
let composing=false;
function serialize() {
  if(editor.innerHTML===originalHTML) return originalMarkdown;
  const pieces=[];
  for (const node of editor.childNodes) {
    if (node.nodeType===Node.TEXT_NODE && !node.textContent.trim()) continue;
    const saved = node.nodeType===Node.ELEMENT_NODE && originals.get(node.dataset.block);
    if (saved && node.innerHTML===saved.html) pieces.push(saved.source.replace(/\n+$/,''));
    else {
      const value=converter.turndown(node.nodeType===Node.TEXT_NODE ? node.textContent : node.outerHTML);
      if(value.trim()) pieces.push(value);
    }
  }
  if(references && pieces.length) pieces.push(references);
  return pieces.join('\n\n')+(pieces.length?'\n':'');
}
function sendChange() {
  if(composing) return;
  const markdown=serialize();
  if(markdown===lastSent) return;
  lastSent=markdown;
  window.webkit?.messageHandlers.changed.postMessage({markdown,revision});
}
function setContent(payload, nextRevision, originalSource, folder='') {
  if(composing) {pendingRemote=[payload,nextRevision,originalSource]; return;}
  const oldScroll=window.scrollY;
  originals=new Map(); references=payload.references; revision=nextRevision;
  editor.replaceChildren();
  for(const block of payload.blocks) {
    const section=document.createElement('section'); section.dataset.block=String(block.id);
    section.innerHTML=block.html;
    for(const input of section.querySelectorAll('input[type=checkbox]')) input.disabled=false;
    for(const image of section.querySelectorAll('img')) {
      const src=image.getAttribute('src');
      if(folder && src && !/^[a-z][a-z0-9+.-]*:/i.test(src)) {image.dataset.relativeSrc=src;image.src=new URL(src,folder).href;}
    }
    originals.set(String(block.id),{html:section.innerHTML,source:block.source});
    editor.append(section);
  }
  if(!editor.children.length) editor.innerHTML='<p><br></p>';
  lastSent=originalSource;originalMarkdown=originalSource;originalHTML=editor.innerHTML;
  window.scrollTo(0,oldScroll);
}
function setBasePath(folder) {
  if(!folder) return;
  const pristine=editor.innerHTML===originalHTML;
  for(const section of editor.children) {
    const saved=originals.get(section.dataset.block);
    const unchanged=saved && section.innerHTML===saved.html;
    for(const image of section.querySelectorAll('img')) {
      const src=image.dataset.relativeSrc || image.getAttribute('src');
      if(src && !/^[a-z][a-z0-9+.-]*:/i.test(src)) {image.dataset.relativeSrc=src;image.src=new URL(src,folder).href;}
    }
    if(unchanged) saved.html=section.innerHTML;
  }
  if(pristine) originalHTML=editor.innerHTML;
}
function format(command, value) {
  editor.focus();
  document.execCommand(command,false,value||null);
  sendChange();
}
editor.addEventListener('input',sendChange);
editor.addEventListener('compositionstart',()=>{composing=true;});
editor.addEventListener('compositionend',()=>{composing=false;sendChange();pendingRemote=null;});
editor.addEventListener('change',event=>{
  if(event.target.type==='checkbox') {
    event.target.toggleAttribute('checked',event.target.checked);
    sendChange();
  }
});
editor.addEventListener('paste',event=>{
  event.preventDefault();
  document.execCommand('insertText',false,event.clipboardData.getData('text/plain'));
  sendChange();
});
editor.addEventListener('keydown',event=>{
  if(event.metaKey && !event.shiftKey && ['b','i'].includes(event.key.toLowerCase())) {
    event.preventDefault();format(event.key.toLowerCase()==='b'?'bold':'italic');
  }
  if(event.metaKey && event.key.toLowerCase()==='z') {
    event.preventDefault();document.execCommand(event.shiftKey?'redo':'undo');sendChange();
  }
});
document.addEventListener('click',event=>{
  const link=event.target.closest('a');
  if(link) {event.preventDefault();if(event.metaKey) window.webkit?.messageHandlers.openLink.postMessage(link.getAttribute('href'));}
});
window.addEventListener('error',event=>window.webkit?.messageHandlers.error.postMessage(event.message));
window.markeer={setContent,setBasePath,serialize,format,editor};
document.execCommand('defaultParagraphSeparator',false,'p');
window.webkit?.messageHandlers.ready.postMessage('ready');
