(function(){
  "use strict";
  var $=function(s,r){return (r||document).querySelector(s)},$$=function(s,r){return Array.prototype.slice.call((r||document).querySelectorAll(s))};
  var root=document.documentElement;
  /* 颜色：自动跟系统；浅色 / 深色记在这一页（localStorage） */
  var TK="askfree-notes-theme";
  function setTheme(t){if(t==="light"||t==="dark")root.setAttribute("data-theme",t);else root.removeAttribute("data-theme");$$(".seg button").forEach(function(b){b.classList.toggle("on",b.dataset.t===(t||"auto"))});try{localStorage.setItem(TK,t||"auto")}catch(e){}}
  var m=location.hash.match(/theme=(light|dark)/);var saved=null;try{saved=localStorage.getItem(TK)}catch(e){}
  setTheme(m?m[1]:saved);
  $$(".seg button").forEach(function(b){b.addEventListener("click",function(){setTheme(b.dataset.t)})});
  /* 目录收起 / 展开：窄于 900 默认收起；记住用户点过的 */
  var CK="askfree-notes-toc",shell=$("#shell"),tgl=$("#tgl");
  function setRail(on,keep){
    var cur=$(".ti.on"),id=cur&&cur.getAttribute("href").slice(1),el=id&&document.getElementById(id),y=el?el.getBoundingClientRect().top:null;
    shell.classList.toggle("rail",on);tgl.setAttribute("aria-label",on?"展开目录":"收起目录");tgl.title=on?"展开目录":"收起目录";
    if(keep&&el&&id!=="ov")scrollBy(0,el.getBoundingClientRect().top-y);   /* 当前那一节停在原位，不跳 */
  }
  var pref=null;try{pref=localStorage.getItem(CK)}catch(e){}
  if(/toc=rail/.test(location.hash))pref="rail";
  setRail(pref?pref==="rail":innerWidth<900,false);
  tgl.addEventListener("click",function(){var on=!shell.classList.contains("rail");setRail(on,true);try{localStorage.setItem(CK,on?"rail":"open")}catch(e){};hideTip()});
  /* 细条上指着编号显示这一节的名字 */
  var tip=null;function hideTip(){tip&&tip.remove();tip=null}
  $$(".ti").forEach(function(a){a.addEventListener("mouseenter",function(){if(!shell.classList.contains("rail"))return;var r=a.getBoundingClientRect();tip=document.createElement("div");tip.className="tip";tip.textContent=a.dataset.tip;tip.style.left=(r.right+8)+"px";tip.style.top=(r.top+4)+"px";document.body.appendChild(tip)});a.addEventListener("mouseleave",hideTip)});
  /* 跟着滚动标出当前这一节 */
  var secs=[$("#ov")].concat($$(".sec"));
  function spy(){var cur="ov";secs.forEach(function(s){if(s.getBoundingClientRect().top<=140)cur=s.id});if(innerHeight+scrollY>=document.documentElement.scrollHeight-4)cur=secs[secs.length-1].id;$$(".ti").forEach(function(a){a.classList.toggle("on",a.getAttribute("href")==="#"+cur)})}
  addEventListener("scroll",spy,{passive:true});spy();
  /* 放大截图 */
  $$("[data-zoom]").forEach(function(a){function open(e){e.preventDefault();var lb=document.createElement("div");lb.className="lb";lb.innerHTML='<img alt="">';lb.firstChild.src=a.querySelector("img").src;lb.addEventListener("click",function(){lb.remove()});document.body.appendChild(lb)}a.addEventListener("click",open);a.addEventListener("keydown",function(e){if(e.key==="Enter"||e.key===" ")open(e)})});
  addEventListener("keydown",function(e){if(e.key==="Escape"){var lb=$(".lb");lb&&lb.remove()}});
  /* 复制代码 */
  $$("[data-copy]").forEach(function(b){var html=b.innerHTML;b.addEventListener("click",function(){var c=b.closest(".code").querySelector("pre").innerText;navigator.clipboard&&navigator.clipboard.writeText(c);b.innerHTML='<svg viewBox="0 0 16 16"><path d="M3.6 8.4 6.6 11.3 12.4 4.8"/></svg>已复制';setTimeout(function(){b.innerHTML=html},1500)})});
  /* 横向放不下：右端渐隐，滚到头去掉 */
  function fade(x){x.classList.toggle("end",x.scrollLeft+x.clientWidth>=x.scrollWidth-1)}
  $$(".scrollx").forEach(function(x){fade(x);x.addEventListener("scroll",function(){fade(x)},{passive:true})});
  addEventListener("resize",function(){$$(".scrollx").forEach(fade)});
})();
