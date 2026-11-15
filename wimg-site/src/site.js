const sqFlat=(()=>{// Eichhörnchen fürs Band, Runde 3: Oberkörper, flauschiger Schwanz, Nagezähne
let U=100000;
const C={fur:'#C8692E',furD:'#8A3F17',furL:'#E79A5A',cream:'#F6EAD3',creamS:'#D9C3A0',ink:'#1B1512',den:'#5F86B5',denD:'#2C4A70',st:'#E08A2E',lin:'#F6F1E6',linS:'#BDB3A2',moth:'#B7B0A6',mothD:'#7D766C'};
const r1=v=>Math.round(v*10)/10;
// Schwanz als Kette aus Fellbüscheln entlang einer Kurve
const TAIL={
 up:[[76,90],[102,84],[86,40],[104,24],[124,10],[118,40],[104,36]],
 low:[[74,92],[92,92],[104,78],[112,74],[122,70],[124,90],[114,90]],
 droop:[[80,96],[96,94],[106,100],[108,108],[110,118],[98,122],[96,112]]};
function bez(p0,p1,p2,p3,t){const u=1-t;return [u*u*u*p0[0]+3*u*u*t*p1[0]+3*u*t*t*p2[0]+t*t*t*p3[0],u*u*u*p0[1]+3*u*u*t*p1[1]+3*u*t*t*p2[1]+t*t*t*p3[1]];}
function tail(kind,u){const P=TAIL[kind];const pts=[];
 for(let i=0;i<=12;i++)pts.push(bez(P[0],P[1],P[2],P[3],i/12));
 for(let i=1;i<=6;i++)pts.push(bez(P[3],P[4],P[5],P[6],i/6));
 const k=kind==='droop'?0.72:1;const R=pts.map((_,i)=>{const t=i/(pts.length-1);return k*(7+9*Math.sin(Math.PI*Math.min(1,t*1.25))*(1-0.35*t));});
 let o='',f='',h='';
 pts.forEach(([x,y],i)=>{o+=`<circle cx="${r1(x)}" cy="${r1(y)}" r="${r1(R[i]+1.7)}" fill="${C.furD}"/>`;});
 pts.forEach(([x,y],i)=>{f+=`<circle cx="${r1(x)}" cy="${r1(y)}" r="${r1(R[i])}" fill="url(#tl${u})"/>`;});
 // Fellsträhnen entlang der Mittellinie und Büschel am Rand
 for(let i=1;i<pts.length-1;i+=2){const[x,y]=pts[i],[nx,ny]=pts[i+1];const dx=nx-x,dy=ny-y,l=Math.hypot(dx,dy)||1,ox=-dy/l,oy=dx/l;
  for(const s of[-0.45,0.15]){const sx=x+ox*R[i]*s,sy=y+oy*R[i]*s;h+=`<path d="M${r1(sx)} ${r1(sy)} q${r1(dx*0.5+ox*2)} ${r1(dy*0.5+oy*2)} ${r1(dx*1.1)} ${r1(dy*1.1)}" fill="none" stroke="${s<0?C.furL:'#A9521F'}" stroke-width="1.2" stroke-linecap="round" opacity=".8"/>`;}
  for(const sd of[-1,1]){const ex=x+ox*R[i]*sd,ey=y+oy*R[i]*sd;h+=`<path d="M${r1(ex)} ${r1(ey)} l${r1(ox*sd*2.6+dx*0.25)} ${r1(oy*sd*2.6+dy*0.25)}" stroke="${C.furD}" stroke-width="1.6" stroke-linecap="round"/>`;}}
 const [ex,ey]=pts[pts.length-1];
 return o+f+h+`<circle cx="${r1(ex)}" cy="${r1(ey)}" r="${r1(R[R.length-1]*0.7)}" fill="#A44E1E" opacity=".55"/>`;}
function defs(u){return `<defs>
<radialGradient id="hd${u}" cx="42%" cy="32%" r="72%"><stop offset="0" stop-color="#E4884A"/><stop offset=".65" stop-color="${C.fur}"/><stop offset="1" stop-color="#9F4B1C"/></radialGradient>
<radialGradient id="tl${u}" gradientUnits="userSpaceOnUse" cx="96" cy="44" r="58"><stop offset="0" stop-color="#EA9C5E"/><stop offset=".6" stop-color="#CD6D31"/><stop offset="1" stop-color="#A9521F"/></radialGradient>
<radialGradient id="ck${u}" cx="45%" cy="30%" r="75%"><stop offset="0" stop-color="#FFFAF0"/><stop offset="1" stop-color="#E8D2AE"/></radialGradient>
<radialGradient id="ey${u}" cx="38%" cy="32%" r="72%"><stop offset="0" stop-color="#5A3E2E"/><stop offset=".55" stop-color="${C.ink}"/></radialGradient>
<linearGradient id="ear${u}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F3CDB3"/><stop offset="1" stop-color="#D79878"/></linearGradient>
<pattern id="tw${u}" width="3" height="3" patternUnits="userSpaceOnUse" patternTransform="rotate(-58)"><rect width="3" height="3" fill="${C.den}"/><rect width="1.2" height="3" fill="#7A98C8"/></pattern>
</defs>`;}
function ears(u){return `<path d="M41 40 C36 30 34 20 37 12 C42 16 48 26 52 34 Z M79 40 C84 30 86 20 83 12 C78 16 72 26 68 34 Z" fill="url(#hd${u})" stroke="${C.furD}" stroke-width="1.6" stroke-linejoin="round"/>
<path d="M41.5 34 C39 28 38.5 22 39.5 17 C43 21 46 27 48 32 Z M78.5 34 C81 28 81.5 22 80.5 17 C77 21 74 27 72 32 Z" fill="url(#ear${u})"/>
<path d="M37.5 14 C32 9 33 2 38 -2 C37 3 41 8 40 14 Z M82.5 14 C88 9 87 2 82 -2 C83 3 79 8 80 14 Z" fill="${C.furD}"/>
<path d="M38 11 C35.5 7 36 3 38 0 M82 11 C84.5 7 84 3 82 0" fill="none" stroke="#C9773E" stroke-width=".9" stroke-linecap="round"/>`;}
function face(u,{lid=0,closed=0,cross=0,cheeks=1,py=0,px=0,mouth='m',teeth=true}){let o='';
 o+=`<path d="M32 62 C29 42 42 29 60 29 C78 29 91 42 88 62 C86 73 75 79 60 79 C45 79 34 73 32 62 Z" fill="url(#hd${u})" stroke="${C.furD}" stroke-width="1.8" stroke-linejoin="round"/>`;
 o+=`<path d="M32 60 l-4 2 l4 1.5 l-3 3 l4.5 0 M88 60 l4 2 l-4 1.5 l3 3 l-4.5 0" fill="none" stroke="${C.furD}" stroke-width="1.3" stroke-linejoin="round" stroke-linecap="round"/>`;
 o+=`<path d="M52 31 q4 -5 8 -2 q4 -4 8 2" fill="none" stroke="${C.furD}" stroke-width="1.4" stroke-linecap="round"/><path d="M40 42 q7 -6 15 -4 M80 42 q-7 -6 -15 -4" fill="none" stroke="${C.furL}" stroke-width="1.6" stroke-linecap="round" opacity=".85"/>`;
 const cr=10*cheeks,cy=65+2*(cheeks-1);
 o+=`<ellipse cx="${r1(47-4*(cheeks-1))}" cy="${r1(cy)}" rx="${r1(cr)}" ry="${r1(cr*0.85)}" fill="url(#ck${u})"/><ellipse cx="${r1(73+4*(cheeks-1))}" cy="${r1(cy)}" rx="${r1(cr)}" ry="${r1(cr*0.85)}" fill="url(#ck${u})"/>`;
 o+=`<path d="M51 58 Q60 52 69 58 Q71 72 60 75 Q49 72 51 58 Z" fill="${C.cream}"/>`;
 o+=`<path d="M41 70 q2 2.4 5 2.6 M79 70 q-2 2.4 -5 2.6" fill="none" stroke="${C.creamS}" stroke-width="1.1" stroke-linecap="round"/>`;
 [[48.5,51],[71.5,51]].forEach(([x,y],i)=>{
  if(closed){o+=`<ellipse cx="${x}" cy="${y}" rx="8.6" ry="6.4" fill="${C.cream}" opacity=".75"/><path d="M${x-6.5} ${y+2} Q${x} ${y-5.5*closed} ${x+6.5} ${y+2}" fill="none" stroke="${C.ink}" stroke-width="2.6" stroke-linecap="round"/><path d="M${x+(i?6.5:-6.5)} ${y+1} l${i?2.4:-2.4} -1.6" stroke="${C.ink}" stroke-width="1.3" stroke-linecap="round"/>`;return;}
  const qx=x+(cross?(i?-1.6:1.6):px),qy=y+py;
  o+=`<ellipse cx="${x}" cy="${y}" rx="8" ry="8.4" fill="${C.cream}" opacity=".85"/><ellipse cx="${r1(x+(px||0)*0.4)}" cy="${r1(y+0.4+(py||0)*0.4)}" rx="5.8" ry="6.4" fill="url(#ey${u})"/><circle cx="${r1(qx+1.8)}" cy="${r1(qy-2.2)}" r="2.1" fill="#fff"/><circle cx="${r1(qx-1.8)}" cy="${r1(qy+2.4)}" r=".9" fill="#fff" opacity=".7"/>`;
  o+=`<path d="M${x-5.6} ${y-3.6} Q${x} ${y-8.6} ${x+5.6} ${y-3.6}" fill="none" stroke="${C.ink}" stroke-width="1.3" stroke-linecap="round"/><path d="M${x+(i?5.6:-5.6)} ${y-3.6} l${i?2:-2} -1.6" stroke="${C.ink}" stroke-width="1.3" stroke-linecap="round"/>`;
  if(lid>0){const h=y-7.6+lid*15.2,id=`lid${u}${i}`;o+=`<clipPath id="${id}"><ellipse cx="${x}" cy="${y+0.4}" rx="7.2" ry="7.8"/></clipPath><g clip-path="url(#${id})"><rect x="${x-9}" y="${y-9}" width="18" height="${r1(h-y+9)}" fill="#D3763A"/></g><path d="M${x-6.6} ${r1(h)} Q${x} ${r1(h+1.2)} ${x+6.6} ${r1(h)}" fill="none" stroke="${C.ink}" stroke-width="2" stroke-linecap="round"/>`;}});
 o+=`<path d="M56.6 59.5 Q60 58.2 63.4 59.5 Q62.4 62.6 60 63.4 Q57.6 62.6 56.6 59.5 Z" fill="#5A3326"/><ellipse cx="58.8" cy="60" rx="1.3" ry=".6" fill="#fff" opacity=".6"/>`;
 if(mouth==='o')o+=`<path d="M60 63.4 L60 65" stroke="${C.ink}" stroke-width="1.3"/><ellipse cx="60" cy="68" rx="2.6" ry="2.4" fill="#3A2016"/>`;
 else if(mouth==='f')o+=`<path d="M60 63.4 L60 66 M56 67.4 L64 67.4" fill="none" stroke="${C.ink}" stroke-width="1.5" stroke-linecap="round"/>`;
 else{o+=`<path d="M60 63.4 L60 65.6 M55.4 66.4 Q57.6 68.6 60 65.6 Q62.4 68.6 64.6 66.4" fill="none" stroke="${C.ink}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>`;
  if(teeth)o+=`<path d="M58.3 66.6 L58.3 69.6 Q59.1 70.2 59.9 69.6 L59.9 66.9 M60.1 66.9 L60.1 69.6 Q60.9 70.2 61.7 69.6 L61.7 66.6" fill="#FFFDF8" stroke="#B9A88E" stroke-width=".6"/>`;}
 o+=`<path d="M49 63 L36 60 M49 65.5 L37 67 M71 63 L84 60 M71 65.5 L83 67" stroke="#FFF7EA" stroke-width=".7" opacity=".9" stroke-linecap="round"/>`;
 return o;}
function torso(u){return `<path d="M38 92 C36 80 45 74 60 74 C75 74 84 80 82 92 Z" fill="url(#hd${u})" stroke="${C.furD}" stroke-width="1.6"/><ellipse cx="60" cy="86" rx="13" ry="10" fill="url(#ck${u})"/>`;}
const paw=(x,y,r=0)=>`<g transform="translate(${x} ${y}) rotate(${r})"><rect x="-6.5" y="-6" width="13" height="14" rx="6.5" fill="${C.fur}" stroke="${C.furD}" stroke-width="1.4"/><path d="M-6 4 Q0 9.5 6 4 L5.5 7 Q0 10 -5.5 7 Z" fill="${C.cream}"/><path d="M-2.2 4.5 l0 3.6 M2.2 4.5 l0 3.6" stroke="${C.furD}" stroke-width="1.1" stroke-linecap="round"/><path d="M-4 -3 q2 -2 4 0" fill="none" stroke="${C.furL}" stroke-width="1" opacity=".8"/></g>`;
const note=(x,y,r,c='#8DBE95')=>`<g transform="translate(${x} ${y}) rotate(${r})"><rect x="-13" y="-8" width="26" height="16" rx="2" fill="${c}" stroke="rgba(0,0,0,.28)" stroke-width="1.2"/><rect x="-10" y="-5" width="20" height="10" rx="1" fill="none" stroke="rgba(255,255,255,.4)" stroke-width=".8"/><circle r="3.4" fill="rgba(255,255,255,.55)"/></g>`;
const acorn=(x,y,r=0)=>`<g transform="translate(${x} ${y}) rotate(${r})"><path d="M-6 -1 Q-7 10 0 13 Q7 10 6 -1 Z" fill="#D29A48" stroke="#9A6A26" stroke-width="1.2"/><path d="M-2 2 Q-3 7 -1 9" fill="none" stroke="#F0C27A" stroke-width="1" stroke-linecap="round"/><path d="M-7.5 0 Q-7.5 -7 0 -7 Q7.5 -7 7.5 0 Z" fill="#7A5230"/><path d="M-5 -3 l2 0 M-1 -5 l2 0 M3 -3 l2 0" stroke="#5A3B20" stroke-width=".9"/><path d="M0 -7 l1 -4" stroke="#5A3B20" stroke-width="1.6" stroke-linecap="round"/></g>`;
const moth=(x,y)=>`<g transform="translate(${x} ${y})"><path d="M0 0 C-5 -8 -13 -7 -12 -1 C-11 4 -4 4 0 1 Z M0 0 C5 -8 13 -7 12 -1 C11 4 4 4 0 1 Z" fill="${C.moth}" stroke="${C.mothD}" stroke-width="1"/><path d="M-6 -3 q-2 1 -3 3 M6 -3 q2 1 3 3" fill="none" stroke="${C.mothD}" stroke-width=".7"/><ellipse cy="1" rx="1.8" ry="4" fill="#857C70"/><path d="M-1 -3 q-2 -4 -4 -4 M1 -3 q2 -4 4 -4" fill="none" stroke="#6B645B" stroke-width=".8" stroke-linecap="round"/><circle cx="-1" cy="-1" r=".9" fill="#fff"/><circle cx="1" cy="-1" r=".9" fill="#fff"/></g>`;
function hem(u,inv){let o='';if(inv)o+=`<path d="M20 90 C6 74 -4 80 0 96 C2 104 14 104 22 100 Z M100 90 C114 74 124 80 120 96 C118 104 106 104 98 100 Z" fill="${C.lin}" stroke="${C.linS}" stroke-width="1.4"/><path d="M8 86 q-2 6 2 10 M112 86 q2 6 -2 10" fill="none" stroke="${C.linS}" stroke-width="1"/>`;
 o+=`<path d="M14 88 Q60 85 106 88 L106 122 L14 122 Z" fill="url(#tw${u})" stroke="${C.denD}" stroke-width="1.8"/><path d="M14 88 Q60 85 106 88 L106 97 Q60 95 14 97 Z" fill="#3F6592" opacity=".55"/><path d="M28 87 Q60 93 92 87" fill="#0B1630" opacity=".22"/>`;
 o+=`<path d="M19 93.6 Q60 91.4 101 93.6" fill="none" stroke="${C.st}" stroke-width="1.9" stroke-dasharray="4.2 2.8" stroke-linecap="round"/><path d="M19 103 L101 103" stroke="${C.st}" stroke-width="1.6" stroke-dasharray="4 3" stroke-linecap="round" opacity=".75"/><path d="M19 107 L101 107" stroke="${C.st}" stroke-width="1.6" stroke-dasharray="4 3" stroke-linecap="round" opacity=".55"/>`;
 for(const x of[20,100])o+=`<circle cx="${x}" cy="91" r="2.4" fill="#B9703A" stroke="#7A4520" stroke-width=".8"/><circle cx="${x-0.6}" cy="90.3" r=".8" fill="#F1C79C"/>`;
 return o;}
function sqFlat(state='normal',size=96,opt={}){const u=++U;
 const S0={voll:{t:'up',dy:-2,h:{closed:1,cheeks:1.4,mouth:'m'}},normal:{t:'up',dy:0,h:{px:-0.6,mouth:'m'}},knapp:{t:'low',dy:4,h:{py:1.4,px:1.6,mouth:'f'}},leer:{t:'droop',dy:3,h:{cross:1,cheeks:0.85,mouth:'o'}},gehalt:{t:'up',dy:4,h:{closed:1,mouth:'m'}},yawn:{t:'up',dy:-2,h:{closed:-0.7,mouth:'o',teeth:false}},sleep:{t:'up',dy:3,h:{closed:-1,mouth:'f'}},look:{t:'up',dy:0,h:{px:-2.4,mouth:'m'}}};
 const S=JSON.parse(JSON.stringify(S0[state]));if(opt.blink&&!S.h.closed)S.h.closed=0.15;if(opt.look&&!S.h.closed&&!S.h.cross){S.h.px=opt.look[0];S.h.py=opt.look[1];}
 const base={yawn:'normal',sleep:'normal',look:'normal'}[state]||state;
 let back='',front='';
 if(base==='voll')back+=note(26,78,-22,'#E8BE72')+note(22,68,-34);
 if(base!=='leer')back+=tail(S.t,u);
 back+=torso(u)+`<g transform="translate(0 ${S.dy})">${ears(u)}${face(u,S.h)}</g>`;
 const h=hem(u,base==='leer');
 if(base==='voll'||base==='normal'||base==='leer')front+=paw(50,88)+paw(70,88);
 if(state==='knapp')front+=acorn(60,85,0)+paw(50,88,18)+paw(70,88,-18);
 if(state==='gehalt')front+=note(60,14,-6,'#E8BE72')+paw(47,22,200)+paw(73,22,160);
 if(base==='leer')front+=tail('droop',u)+moth(60,30);
 if(state==='yawn')front=paw(42,40,160)+paw(78,40,200);
 if(opt.z)front+=`<g opacity="${opt.z}" fill="#C9D6E6" font-family="Manrope,sans-serif" font-weight="800"><text x="86" y="${r1(30-opt.z*4)}" font-size="13">z</text><text x="96" y="${r1(18-opt.z*6)}" font-size="10">z</text></g>`;
 return `<svg viewBox="0 0 120 120" width="${size}" height="${size}" style="display:block;overflow:visible" aria-hidden="true">${defs(u)}${back}${h}${front}</svg>`;}

return sqFlat;})();
(function(){
const root=document.documentElement;let q=new URLSearchParams(location.search);
const reduce=matchMedia('(prefers-reduced-motion: reduce)').matches;
// Hell/Dunkel
let th=q.get('theme');{try{th=th||localStorage.getItem('wimg-theme');}catch(e){}
if(!th&&matchMedia('(prefers-color-scheme: dark)').matches)th='D';}if(th)root.dataset.theme=th;
document.querySelectorAll('[data-themebtn]').forEach(b=>b.addEventListener('click',()=>{root.dataset.theme=root.dataset.theme==='D'?'L':'D';try{localStorage.setItem('wimg-theme',root.dataset.theme);}catch(e){}}));

// Ziehen auf dem Schreibtisch
let z=30;
document.querySelectorAll('.desk [data-drag]').forEach(el=>{
 el.addEventListener('pointerdown',e=>{if(innerWidth<1200||e.button>0)return;const desk=el.closest('.desk');const dr=desk.getBoundingClientRect(),r=el.getBoundingClientRect();
  const ox=e.clientX-r.left,oy=e.clientY-r.top;let moved=false;const sx=e.clientX,sy=e.clientY;
  const mv=ev=>{if(!moved&&Math.hypot(ev.clientX-sx,ev.clientY-sy)<4)return;if(!moved){moved=true;el.classList.add('lift');el.style.zIndex=++z;el.style.right='auto';el.style.bottom='auto';}
   el.style.left=(ev.clientX-dr.left-ox)+'px';el.style.top=(ev.clientY-dr.top-oy)+'px';};
  const up=()=>{removeEventListener('pointermove',mv);removeEventListener('pointerup',up);el.classList.remove('lift');if(moved){el.dataset.moved=1;setTimeout(()=>delete el.dataset.moved,0);}};
  addEventListener('pointermove',mv);addEventListener('pointerup',up);});});
// Clips: Tippen zeigt das zweite Bild (auf Touch)
document.querySelectorAll('.clip').forEach(c=>c.addEventListener('click',()=>{if(c.dataset.moved)return;c.classList.toggle('on');}));

// Eichhörnchen: schaut dem Zeiger nach, schaut zum Download-Knopf, wechselt die Laune
const MOODS=[['normal','Normal: alles im Rahmen.'],['voll','Voll: Backen voll, Monat läuft gut.'],['knapp','Knapp: die letzte Eichel, gut einteilen.'],['leer','Leer: Die Motte findet’s gemütlich. Gehalt kommt bald.'],['gehalt','Gehalt ist da! Neuer Monat.']];
let sq=null,mood=0,look=[0,0],target=null,blink=0,raf=0,pointer=null;
function draw(){raf=0;if(!sq)return;let lk=[0,0];const r=sq.getBoundingClientRect();const cx=r.left+r.width*0.5,cy=r.top+r.height*0.43;
 const tp=target?(()=>{const b=target.getBoundingClientRect();return [b.left+b.width/2,b.top+b.height/2];})():pointer;
 if(tp){const dx=tp[0]-cx,dy=tp[1]-cy,d=Math.hypot(dx,dy)||1,k=Math.min(1,d/220);lk=[dx/d*2.4*k,dy/d*2*k];}
 sq.innerHTML=sqFlat(MOODS[mood][0],230,{look:lk,blink:blink});}
const req=()=>{if(!raf)raf=requestAnimationFrame(draw);};
function setupSq(){sq=[...document.querySelectorAll('[data-sq]')].find(e=>e.offsetParent!==null)||null;req();}
addEventListener('pointermove',e=>{pointer=[e.clientX,e.clientY];req();},{passive:true});
addEventListener('scroll',req,{passive:true});
document.querySelectorAll('[data-dl]').forEach(b=>{b.addEventListener('pointerenter',()=>{target=b;req();if(sq&&!reduce){sq.classList.add('hop');setTimeout(()=>sq&&sq.classList.remove('hop'),260);}});b.addEventListener('pointerleave',()=>{target=null;req();});b.addEventListener('focus',()=>{target=b;req();});b.addEventListener('blur',()=>{target=null;req();});});
function tapSq(){mood=(mood+1)%MOODS.length;draw();const m=sq.closest('.host').querySelector('.mood');m.textContent=MOODS[mood][1];m.classList.add('show');clearTimeout(m._t);m._t=setTimeout(()=>m.classList.remove('show'),2600);}
document.querySelectorAll('[data-sq]').forEach(s=>{s.addEventListener('click',tapSq);s.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();tapSq();}});});
// Blinzeln alle 4–8 s
(function bl(){setTimeout(()=>{if(!reduce&&sq){blink=1;draw();setTimeout(()=>{blink=0;draw();},160);}bl();},4000+Math.random()*4000);})();
// Unten: umarmt die Eichel und hüpft einmal, wenn der Fuß der Seite sichtbar wird
const ft=document.querySelector('[data-foot]');
if(ft&&'IntersectionObserver' in window){new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting&&!reduce){ft.style.transform='translateX(-50%) translateY(-10px)';setTimeout(()=>ft.style.transform='',300);}}),{threshold:.6}).observe(ft);}
setupSq();
})();
