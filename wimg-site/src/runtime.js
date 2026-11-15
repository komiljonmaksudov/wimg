
class DCLogic{constructor(p){this.props=p;this.state={};} setState(o){Object.assign(this.state,typeof o==='function'?o(this.state):o); schedule();} forceUpdate(){schedule();}}
const inst={};
function mk(name,key,props){ if(!inst[key]){const C=new Function('DCLogic',F[name].code+';return Component;')(DCLogic); inst[key]=new C(props); if(inst[key].componentDidMount) setTimeout(()=>inst[key].componentDidMount()); } inst[key].props=props; return inst[key];}
const look=(e,sc)=>{e=e.trim(); if(e==='true')return true; if(e==='false')return false; if(/^-?\d+(\.\d+)?$/.test(e))return +e; const p=e.split('.'); for(let i=sc.length-1;i>=0;i--){ if(p[0] in sc[i]){let v=sc[i][p[0]]; for(const q of p.slice(1)) v=v==null?v:v[q]; return v;}} };
const interp=(s,sc)=>{const w=s.match(/^\s*\{\{([^}]*)\}\}\s*$/); if(w)return look(w[1],sc); return s.replace(/\{\{([^}]*)\}\}/g,(_,e)=>{const v=look(e,sc);return v==null?'':String(v);});};
const tpls={};
function build(name,key,props,out){ const c=mk(name,key,props); const vals=c.renderVals(); if(!tpls[name]){const t=document.createElement('template'); t.innerHTML=F[name].tpl; tpls[name]=t;} let n=0;
  const walk=(node,sc,op,kp)=>{ if(node.nodeType===3){const s=String(interp(node.nodeValue,sc)??''); if(s.trim()||op.childNodes.length) op.appendChild(document.createTextNode(s)); return;} if(node.nodeType!==1)return; const tag=node.localName;
    if(tag==='sc-for'){(look(node.getAttribute('list').replace(/[{}]/g,''),sc)||[]).forEach((it,i)=>node.childNodes.forEach(ch=>walk(ch,sc.concat([{[node.getAttribute('as')]:it,$index:i}]),op,kp+'.'+(it&&it.id!=null?it.id:i))));return;}
    if(tag==='sc-if'){ if(look(node.getAttribute('value').replace(/[{}]/g,''),sc)) node.childNodes.forEach(ch=>walk(ch,sc,op,kp)); return;}
    if(tag==='dc-import'){ const p={}; for(const a of node.attributes){ if(a.name==='name'||a.name.startsWith('hint-'))continue; p[a.name.replace(/-([a-z])/g,(_,c)=>c.toUpperCase())]=interp(a.value,sc);} const nm=node.getAttribute('name'); const d=document.createElement('div'); d.style.display='contents'; build(nm,key+'/'+nm+(n++)+JSON.stringify(p),p,d); op.appendChild(d); return;}
    const el=node.namespaceURI==='http://www.w3.org/2000/svg'?document.createElementNS(node.namespaceURI,tag):document.createElement(tag);
    for(const a of node.attributes){ const v=interp(a.value,sc); if(a.name.startsWith('on')){ if(typeof v==='function') el['__'+a.name.slice(2).toLowerCase()]=v; continue;} if(v===false||v==null)continue; el.setAttribute(a.name==='classname'?'class':a.name,v===true?'':String(v)); }
    (node.content?node.content.childNodes:node.childNodes).forEach(ch=>walk(ch,sc,el,kp)); op.appendChild(el); };
  tpls[name].content.childNodes.forEach(ch=>walk(ch,[vals],out,'')); }
// morph: patch live DOM to match fresh DOM, by position
function morph(a,b){
  if(a.nodeType!==b.nodeType||a.nodeName!==b.nodeName){a.replaceWith(b);return;}
  if(a.nodeType===3){if(a.nodeValue!==b.nodeValue)a.nodeValue=b.nodeValue;return;}
  for(const at of Array.from(a.attributes)) if(!b.hasAttribute(at.name)) a.removeAttribute(at.name);
  for(const at of Array.from(b.attributes)) if(a.getAttribute(at.name)!==at.value) a.setAttribute(at.name,at.value);
  for(const k of Object.keys(b)) if(k.startsWith('__')) a[k]=b[k];
  for(const k of Object.keys(a)) if(k.startsWith('__')&&!(k in b)) delete a[k];
  const ac=Array.from(a.childNodes), bc=Array.from(b.childNodes);
  for(let i=0;i<bc.length;i++){ if(i<ac.length) morph(ac[i],bc[i]); else a.appendChild(bc[i]); }
  for(let i=bc.length;i<ac.length;i++) ac[i].remove();
}
let pend=false; function schedule(){ if(pend)return; pend=true; requestAnimationFrame(()=>{pend=false; render();}); }
function render(){ const root=document.getElementById('root'); const d=document.createElement('div'); build(TOP,'top',{},d); if(!root.firstChild){ while(d.firstChild) root.appendChild(d.firstChild);} else { const tmp=document.createElement('div'); tmp.id='root'; while(d.firstChild) tmp.appendChild(d.firstChild); morph(root,tmp);} }
['click','input','change','keydown','pointerdown'].forEach(ev=>document.addEventListener(ev,e=>{ let n=e.target; while(n&&n!==document){ if(n['__'+ev]){ n['__'+ev](e); return;} n=n.parentNode; } }));
render();
