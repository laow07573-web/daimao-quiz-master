'use strict';
(()=>{
 const root=document.documentElement, reduced=matchMedia('(prefers-reduced-motion: reduce)'),toggle=document.querySelector('.motion-toggle');
 let userPaused=false, timer=null, tick=0;
 const texts={刷题:'答完即时核对，边做边发现没弄懂的地方。',练习:'限时或不限时，使用答题卡，完成整轮后统一提交。',背题:'直接查看答案，按顺序回顾知识点，不记入刷题统计。'};
 const modes=[...document.querySelectorAll('[data-mode]')],screens=[...document.querySelectorAll('[data-screen]')],steps=[...document.querySelectorAll('.ai-step')];
 function visible(el){const r=el.getBoundingClientRect();return r.bottom>0&&r.top<innerHeight;}
 function choose(b,manual=false){modes.forEach(x=>x.setAttribute('aria-pressed',String(x===b)));const panel=document.querySelector('.demo-copy');panel.textContent=texts[b.dataset.mode];panel.classList.remove('pop');void panel.offsetWidth;panel.classList.add('pop');if(manual){userPaused=true;sync();}}
 modes.forEach(b=>b.addEventListener('click',()=>choose(b,true)));
 screens.forEach(b=>b.addEventListener('click',()=>{const stage=document.querySelector('.screen-stage');stage.classList.remove('changing');void stage.offsetWidth;stage.classList.add('changing')}));
 function advance(){if(document.hidden)return;tick++;const gallery=document.querySelector('.app-gallery');if(gallery&&visible(gallery)&&!gallery.matches(':hover,:focus-within')){const i=screens.findIndex(x=>x.getAttribute('aria-pressed')==='true');screens[(i+1)%screens.length].click();}if(visible(document.querySelector('.notes'))){steps.forEach((s,i)=>s.classList.toggle('active',i===tick%steps.length));}}
 function sync(){clearInterval(timer);timer=null;const paused=userPaused||reduced.matches;root.classList.toggle('paused',paused);toggle.setAttribute('aria-pressed',String(paused));toggle.textContent=reduced.matches?'已减弱动态效果':paused?'播放动画':'暂停动画';toggle.disabled=reduced.matches;if(!paused)timer=setInterval(advance,3500);}
 toggle.addEventListener('click',()=>{userPaused=!userPaused;sync()});reduced.addEventListener('change',sync);document.addEventListener('visibilitychange',()=>{root.classList.toggle('tab-hidden',document.hidden);sync()});sync();
 const reveals=[...document.querySelectorAll('.heading,.feature,.explorer,.notes,.copy,.values article,.faq-layout,.download')];
 if('IntersectionObserver' in window){const observer=new IntersectionObserver(entries=>entries.forEach(e=>{if(e.isIntersecting){e.target.classList.add('seen');observer.unobserve(e.target)}}),{threshold:.08});reveals.forEach((el,i)=>{el.classList.add('reveal');el.style.setProperty('--stagger',(i%3)*70+'ms');observer.observe(el)});root.classList.add('motion-ready');}
 let pending=false;function scroll(){if(pending)return;pending=true;requestAnimationFrame(()=>{const max=root.scrollHeight-innerHeight;document.querySelector('.scroll-meter').style.transform=`scaleX(${max>0?scrollY/max:0})`;pending=false})}addEventListener('scroll',scroll,{passive:true});addEventListener('resize',scroll);scroll();
})();
