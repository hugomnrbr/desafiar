(()=>{
  const cfg=window.SUPABASE_CONFIG||{};
  const ready=!!(window.supabase&&cfg.url&&!String(cfg.url).includes('COLE_AQUI')&&cfg.key&&!String(cfg.key).includes('COLE_AQUI'));
  const sb=ready?window.supabase.createClient(cfg.url,cfg.key):null;
  const S={resultSoundPlayed:false,clockToken:0,route:'home',premium:{coins:0,owned:[],active:{}},inventoryItems:[],category:'Geral',mode:'1v1',questions:[],questionIndex:0,matchId:null,match:null,myScore:0,seconds:10,timeLimit:10,timer:null,answered:false,waiting:false,user:null,profile:null,isAdmin:false,realtime:null,poll:null,fiftyUsed:false,plusUsed:false,profileTargetId:null,profileDetails:null,adminQuestions:[],adminSearch:'',adminCategory:'Todos',rankRows:null,rankCategory:'__global__',topicCategory:'',topicRows:null,topicStats:null,recentRows:null,friendRows:null,categories:[],categorySearch:'',achievementsRows:null,notifications:[],notificationUnread:0,notificationActors:{},notificationsLoaded:false,notificationRealtime:null,enterMultiplayer:false,adminCategories:[],adminCategorySubmissions:[],adminAchievements:[],adminAchievementSearch:'',premiumItems:[],storeSettings:{enabled:true,cosmetics_enabled:true,vip_enabled:true,coins_enabled:true,pass_enabled:true},adminPremiumItems:[],chatTargetId:null,chatTarget:null,chatRows:[],challengeRows:[],challengeTargetId:null,challengeModal:false,challengeSearch:'',searching:false,searchStartedAt:0,searchTimer:null,botOffer:false,challengeRealtime:null,accessToken:null,forfeitSent:false,botMode:false,bot:null,asyncMode:false,asyncChallengeId:null,asyncProgress:0,asyncStartedAt:0,asyncAnswered:false,asyncFeedbackUntil:0,asyncAdvanceTimer:null,matchPlayers:{},matchCountdown:0,countdownTimer:null,matchSyncTimer:null,presenceTimer:null,resultPresenceTimer:null,rematchMessage:'',transitionUntil:0,transitionQuestion:-1,queueAvatars:[],queueAvatarsTimer:null,emojiOpen:false,matchReactions:[],lastReaction:'',lastAdded:0,lastReactionAt:0,lastCoinsEarned:0,backgrounded:false,timeoutInFlight:false,lastClockSecond:null,answerVisual:{},clockOffsetMs:0,clockSyncToken:0,clockSyncKey:'',clockBaseLocalMs:0,clockBaseServerMs:0,soundOn:localStorage.getItem('quizup_sound')!=='off',audio:null};
  const CATS=[['Geral','🌐','c1'],['Ciência','⚗','c2'],['Entretenimento','🎬','c3'],['Esportes','⚽','c4'],['História','🏛','c5'],['Geografia','📍','c6']];
  const catFallback=()=>CATS.map((c,i)=>({id:`default-${i}`,name:c[0],icon:c[1],parent_id:null,approved:true}));
  const catClass=i=>['c1','c2','c3','c4','c5','c6'][i%6];
  const $=s=>document.querySelector(s), $$=s=>document.querySelectorAll(s), esc=s=>String(s??'').replace(/[&<>\"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#039;'}[m]));
  function audio(){if(!S.soundOn)return null;try{if(!S.audio)S.audio=new (window.AudioContext||window.webkitAudioContext)();if(S.audio.state==='suspended')S.audio.resume();return S.audio}catch(e){return null}}
  function tone(freq,dur=.12,type='sine',gain=.045,delay=0){const a=audio();if(!a)return;const o=a.createOscillator(),g=a.createGain();o.type=type;o.frequency.setValueAtTime(freq,a.currentTime+delay);g.gain.setValueAtTime(.0001,a.currentTime+delay);g.gain.exponentialRampToValueAtTime(gain,a.currentTime+delay+.01);g.gain.exponentialRampToValueAtTime(.0001,a.currentTime+delay+dur);o.connect(g).connect(a.destination);o.start(a.currentTime+delay);o.stop(a.currentTime+delay+dur+.02)}
  function sound(name){if(!S.soundOn)return;audio();if(name==='click')tone(520,.06,'sine',.025);else if(name==='count')tone(620,.16,'triangle',.06);else if(name==='go'){tone(740,.14,'triangle',.07);tone(980,.2,'triangle',.06,.1)}else if(name==='correct'){tone(660,.1,'sine',.045);tone(880,.18,'sine',.05,.08)}else if(name==='wrong'){tone(180,.16,'sawtooth',.035);tone(120,.2,'sawtooth',.025,.08)}else if(name==='timeout'){tone(260,.14,'square',.035);tone(190,.28,'square',.025,.12)}else if(name==='match'){tone(440,.12,'triangle',.04);tone(660,.12,'triangle',.05,.1);tone(990,.25,'triangle',.065,.2)}else if(name==='win'){tone(523,.12,'triangle',.05);tone(659,.12,'triangle',.055,.12);tone(784,.3,'triangle',.07,.24)}else if(name==='lose'){tone(330,.16,'sine',.04);tone(247,.3,'sine',.035,.14)}}
  function av(v='J',c='avatar',url=''){return url?`<img class="${c} avatar-img" src="${esc(url)}" alt="Avatar">`:`<div class="${c}">${esc(v).slice(0,1).toUpperCase()}</div>`}
  function go(r){S.clockToken++;clearInterval(S.timer);clearTimeout(S.poll);clearInterval(S.searchTimer);clearInterval(S.countdownTimer);clearInterval(S.matchSyncTimer);S.matchSyncTimer=null;clearInterval(S.presenceTimer);S.presenceTimer=null;clearInterval(S.resultPresenceTimer);S.resultPresenceTimer=null;clearInterval(S.queueAvatarsTimer);S.queueAvatarsTimer=null;if(S.realtime&&r!=='chat'){sb?.removeChannel(S.realtime);S.realtime=null}S.route=r;try{sessionStorage.setItem('quizup_route',r);sessionStorage.setItem('quizup_match_id',S.matchId||'');sessionStorage.setItem('quizup_async_id',S.asyncChallengeId||'');}catch(e){}render()}
  function sendForfeit(){if(!sb||!S.matchId||S.botMode||S.forfeitSent||!S.user)return; if(S.asyncMode)return; if(S.route!=='game'&&S.route!=='match')return; S.forfeitSent=true; const url=String(cfg.url).replace(/\/$/,'')+'/rest/v1/rpc/forfeit_match'; const body=JSON.stringify({p_match_id:S.matchId}); const headers={'Content-Type':'application/json','apikey':cfg.key,'Authorization':`Bearer ${S.accessToken||''}`,'Prefer':'return=minimal'}; try{fetch(url,{method:'POST',headers,body,keepalive:true,credentials:'omit'}).catch(()=>{})}catch(e){}}
  // Não abandone a partida quando o navegador for para segundo plano.
  // Em celulares, pagehide/beforeunload pode disparar ao trocar de aplicativo.
  function goProfile(id=S.user?.id){S.profileTargetId=id;S.profileDetails=null;go('profile')}
  function top(){
    if(['game','async-game','match','result'].includes(S.route))return '';
    const titles={home:'Início',store:'Loja',categories:'Categorias',topic:S.topicCategory||'Tópico',ranking:'Ranking',profile:S.profileTargetId===S.user?.id?'Meu Perfil':'Perfil',friends:'Amigos',chat:S.chatTarget?.username||'Chat',notifications:'Notificações',achievements:'Conquistas',contribute:'Criar conteúdo',admin:'Painel'};
    const title=titles[S.route]||'QuizUp';
    return `<header class="classic-top"><button class="top-gear" id="classicHome" title="Voltar ao início">⌂</button><b>${esc(title)}</b><div class="top-right"><button class="top-icon" id="topSearch" title="Pesquisar">⌕</button>${S.user?`<button class="top-icon store-top-btn" id="storeBtn" title="Loja">🛒</button><span class="top-coin-pill">⚡ ${Number(S.profile?.coins??S.premium.coins??0).toLocaleString('pt-BR')}</span><button class="top-icon notify-btn" id="notificationsBtn" title="Notificações">●${S.notificationUnread>0?`<span class="notify-badge">${S.notificationUnread>99?'99+':S.notificationUnread}</span>`:''}</button><button class="top-avatar" id="topProfile">${profileAvatarMarkup(S.profile,'avatar mini')}</button>${S.isAdmin?'<button class="top-icon" id="adminBtn">⚙</button>':''}<button class="top-icon" id="logoutTop" title="Sair da conta">↪</button>`:''}</div></header>`;
  }

  function bottom(){
    if(['game','async-game','match','result','login','signup','admin','contribute','chat','topic'].includes(S.route))return '';
    return `<nav class="classic-bottom"><button data-r="home" class="classic-nav"><span>⌂</span><small>Início</small></button><button data-r="categories" class="classic-nav"><span>▦</span><small>Categorias</small></button><button id="quickPlay" class="classic-play"><span>ϟ</span></button><button data-r="friends" class="classic-nav"><span>♧</span><small>Amigos</small></button><button data-r="notifications" class="classic-nav"><span>♟</span><small>Notícias</small></button></nav>`;
  }

  function render(){document.getElementById('app').innerHTML=`<div class="app">${top()}${view()}</div>${bottom()}`;bind();nav()}
  function nav(){$$('.classic-bottom button').forEach(b=>b.classList.toggle('active',b.dataset.r===S.route))}
  function view(){if(!S.user&&!['login','signup'].includes(S.route))return login();if(S.route==='login')return login();if(S.route==='signup')return signup();if(S.route==='home')return home();if(S.route==='store')return premiumStore();if(S.route==='categories')return categories();if(S.route==='topic')return topic();if(S.route==='contribute')return contribute();if(S.route==='match')return match();if(S.route==='game')return game();if(S.route==='async-game')return asyncGame();if(S.route==='result')return result();if(S.route==='ranking')return rank();if(S.route==='profile')return profile();if(S.route==='friends')return friends();if(S.route==='chat')return chat();if(S.route==='notifications')return notificationsView();if(S.route==='admin')return admin();return achievements()}

  function login(){return `<div class="card pad auth-card"><div class="bolt auth-logo">ϟ</div><h1>Entrar no QuizUp</h1><p class="subtitle">Use seu nome de usuário ou e-mail para entrar.</p><form id="loginForm" class="form" style="text-align:left;margin-top:20px"><label>Nome de usuário ou e-mail</label><input id="identifier" required autocomplete="username" placeholder="usuario ou seu@email.com"><label>Senha</label><input id="password" type="password" required autocomplete="current-password" placeholder="••••••••"><button class="primary">ENTRAR</button></form><button class="secondary" id="signupGo">CRIAR CONTA</button>${!ready?'<div class="notice" style="margin-top:12px">Supabase não configurado. Configure <b>config.js</b> para entrar no multiplayer.</div>':''}</div>`}
  function signup(){return `<div class="card pad"><div class="title">Criar conta</div><div class="subtitle">Seu nome de usuário e e-mail precisam ser únicos.</div><form id="signupForm" class="form" style="margin-top:18px"><label>Nome de usuário</label><input id="username" required minlength="3" maxlength="20" pattern="[A-Za-z0-9_]{3,20}" autocomplete="username" placeholder="Ex.: Jogador123"><small class="muted">Use de 3 a 20 caracteres: letras, números e _</small><label>E-mail</label><input id="email" type="email" required autocomplete="email" placeholder="seu@email.com"><label>Senha</label><input id="password" type="password" required minlength="6" pattern="[A-Za-z0-9]{6,}" autocomplete="new-password" placeholder="mínimo 6 caracteres, letras e números"><small class="muted">A senha deve ter no mínimo 6 caracteres e usar somente letras e números.</small><button class="primary">CRIAR CONTA</button></form><button class="secondary" id="loginGo">JÁ TENHO CONTA</button></div>`}
  function home(){
    const p=S.profile||{}; const rec=S.recentRows||[]; const draws=Number(p.draws||rec.filter(r=>r.outcome==='draw').length||0); const games=Number(p.wins||0)+Number(p.losses||0)+draws;
    if(!S.recentRows) setTimeout(loadRecentResults,0);
    return `<section class="classic-home">
      <div class="home-hero ${p.premium_theme?'premium-theme-'+esc(p.premium_theme):''}" style="--cover:${JSON.stringify(p.avatar_url||'')}" >${profileAvatarMarkup(p,'avatar home-avatar')}<div class="home-name ${p.premium_vip||p.premium_title?'premium-name-glow':''}"><h1>${esc(p.username||p.display_name||'Jogador')}</h1><div>${esc(p.premium_title||'')} ${p.premium_vip?'<em class="premium-badge">VIP</em>':''} • Nível ${p.level||1}</div></div><div class="home-stats"><span><b>${games}</b><small>JOGOS</small></span><span><b>${p.wins||0}</b><small>VITÓRIAS</small></span><span><b>${p.losses||0}</b><small>DERROTAS</small></span><span><b>${draws}</b><small>EMPATES</small></span></div></div>
      <div class="home-coin-strip"><span>⚡ ${Number(p.coins||0).toLocaleString('pt-BR')} QuizCoins</span><small>Ganhe moedas jogando • vitória +25%</small></div><button class="classic-myquiz" id="play"><span>✦</span><div><b>MEU QUIZUP</b><small>Jogar agora e continuar evoluindo</small></div><strong>›</strong></button>
      <div class="classic-section-head"><b>Meus tópicos</b><button data-go="categories">VER TODAS</button></div>
      <div class="followed-grid">${(S.categories||catFallback()).slice(0,8).map((c,i)=>`<button class="followed-topic ${catClass(i)}" data-topic="${esc(c.name)}"><span>${esc(c.icon||'✦')}</span><b>${esc(c.name)}</b><small>Nível ${topicLevel(c.name)}</small></button>`).join('')}</div>
      <div class="classic-section-head"><b>Atividade recente</b><button data-go="ranking">RANKING</button></div>
      <div class="activity-feed">${rec.length?rec.slice(0,4).map(r=>`<div class="activity-item"><div class="activity-dot">${r.won?'✓':'×'}</div><div><b>${r.won?'Você venceu':'Você jogou'} em ${esc(r.category)}</b><small>${r.score} pontos • ${new Date(r.created_at).toLocaleDateString('pt-BR')}</small></div></div>`).join(''):'<div class="classic-empty">Jogue sua primeira partida para começar seu histórico.</div>'}</div>
      <div class="classic-shortcuts"><button data-go="store">🛒 Loja</button><button data-go="friends">♧ Amigos</button><button data-go="achievements">★ Conquistas</button><button data-go="profile">♙ Perfil</button></div>
    </section>`;
  }

  function categories(){
    const cats=S.categories.length?S.categories:catFallback(); const term=S.categorySearch.trim().toLowerCase();
    const filtered=cats.filter(c=>!term||c.name.toLowerCase().includes(term)||(c.description||'').toLowerCase().includes(term));
    const mains=filtered.filter(c=>!c.parent_id), subs=filtered.filter(c=>c.parent_id);
    const renderCat=(c,i)=>`<button class="cat classic-cat ${catClass(i)}" data-cat="${esc(c.name)}"><span>${esc(c.icon||'✦')}</span><b>${esc(c.name)}</b><small>Nível ${topicLevel(c.name)}</small></button>`;
    return `<section class="classic-page"><div class="classic-banner"><b>Escolha seu próximo desafio</b><span>Compita em tópicos e suba de nível em cada um deles.</span></div><div class="searchbar classic-search"><input id="categorySearch" value="${esc(S.categorySearch)}" placeholder="🔎 Buscar tópicos"><button id="clearCategorySearch" type="button">×</button></div><div class="classic-section-head"><b>Novos e atualizados</b><button id="contributeGo">CRIAR</button></div><div class="topic-grid">${mains.slice(0,12).map(renderCat).join('')}</div>${subs.length?`<div class="classic-section-head"><b>Subtópicos</b></div><div class="topic-grid">${subs.map(renderCat).join('')}</div>`:''}<div class="classic-section-head"><b>Todos os tópicos</b></div><div class="topic-list">${filtered.slice(0,60).map((c,i)=>`<button class="topic-list-row" data-cat="${esc(c.name)}"><span class="topic-icon ${catClass(i)}">${esc(c.icon||'✦')}</span><span><b>${esc(c.name)}</b><small>${c.parent_id?'Subtópico':'Tópico'} • Nível ${topicLevel(c.name)}</small></span><strong>›</strong></button>`).join('')||'<div class="classic-empty">Nenhum tópico encontrado.</div>'}</div></section>`;
  }
  function topicLevel(category){
    const rows=(S.recentRows||[]).filter(r=>r.category===category); const xp=rows.reduce((n,r)=>n+Number(r.score||0),0); return Math.max(1,1+Math.floor(xp/1000));
  }
  async function loadRecentResults(){if(!sb||!S.user)return;const {data}=await sb.from('game_results').select('category,score,won,outcome,created_at').eq('user_id',S.user.id).order('created_at',{ascending:false}).limit(40);S.recentRows=data||[];render()}
  async function loadTopicData(){if(!sb||!S.user||!S.topicCategory)return;const [{data:mine},{data:ranking}]=await Promise.all([sb.from('game_results').select('score,won,created_at').eq('user_id',S.user.id).eq('category',S.topicCategory),sb.rpc('get_topic_ranking',{p_category:S.topicCategory,p_limit:20})]);const rows=mine||[];const xp=rows.reduce((n,r)=>n+Number(r.score||0),0);S.topicStats={xp,games:rows.length,wins:rows.filter(r=>r.won).length,losses:rows.filter(r=>!r.won).length,level:Math.max(1,1+Math.floor(xp/1000))};S.topicRows=ranking||[];render()}
  function topic(){if(!S.topicStats){setTimeout(loadTopicData,0);return `<section class="topic-detail loading-topic"><div class="rings small-rings"><div class="big">ϟ</div></div><div class="muted">Carregando tópico...</div></section>`}const t=S.topicStats;const pct=Math.min(100,(t.xp%1000)/10);return `<section class="topic-detail"><div class="topic-cover"><span class="topic-cover-icon">✦</span><h1>${esc(S.topicCategory)}</h1><p>Nível ${t.level}</p></div><button class="classic-big-play" id="topicPlay">JOGAR AGORA <span>⚡</span></button><div class="topic-progress"><div class="progress-head"><b>Nível ${t.level}</b><span>${t.xp%1000} / 1000 XP</span></div><div class="topic-progress-bar"><i style="width:${pct}%"></i></div></div><div class="classic-stat-grid"><div><b>${t.games}</b><small>JOGOS</small></div><div><b>${t.wins}</b><small>VITÓRIAS</small></div><div><b>${t.losses}</b><small>DERROTAS</small></div><div><b>${t.games?Math.round(t.wins/t.games*100):0}%</b><small>VITÓRIAS</small></div></div><div class="classic-section-head"><b>Ranking de ${esc(S.topicCategory)}</b><button id="topicRanking">VER RANKING</button></div><div class="list topic-ranking">${(S.topicRows||[]).slice(0,10).map((r,i)=>`<button class="row player-row" data-profile="${r.id}"><b>#${i+1}</b>${profileAvatarMarkup(r,'avatar mini')}<div><b>${esc(r.username||r.display_name||'Jogador')}</b><div class="premium-game-identity">${profileIdentityMarkup(r)}</div><div class="muted">Nível ${r.level||1} • ${r.wins||0} vitórias</div></div><strong>${r.topic_xp||0}</strong></button>`).join('')||'<div class="classic-empty">Ainda não há jogadores classificados neste tópico.</div>'}</div><button class="secondary" id="backTopics">← VOLTAR AOS TÓPICOS</button></section>`}


  function premiumLoad(){try{const raw=localStorage.getItem('quizup_premium');if(raw)S.premium={...S.premium,...JSON.parse(raw)}}catch(e){}}
  function premiumSave(){localStorage.setItem('quizup_premium',JSON.stringify(S.premium))}
  function premiumActive(){return S.premium?.active||{}}
  function premiumBadge(){return S.premium?.owned?.includes('vip')||S.profile?.premium_vip?'<em class="premium-badge">VIP</em>':''}
  function activeCosmeticsFor(profile=S.profile){
    const isOther=!!(profile?.id&&S.user?.id&&profile.id!==S.user.id);
    const a=isOther?{}:premiumActive();
    return {
      frame: profile?.premium_frame || a.frame || '',
      effect: profile?.premium_effect || a.effect || '',
      theme: profile?.premium_theme || a.theme || '',
      avatar: profile?.premium_avatar || a.avatar || '',
      title: profile?.premium_title || a.title || '',
      badge: profile?.premium_badge || a.badge || ''
    };
  }
  function cosmeticsMarkup(profile, avatarClass='avatar mini', extra=''){
    const c=activeCosmeticsFor(profile);
    const frame=c.frame?` premium-frame ${esc(c.frame)}`:'';
    const vip=profile?.premium_vip?'<em class="premium-badge">VIP</em>':'';
    const glow=(profile?.premium_vip||c.title||c.frame||c.theme)?' premium-name-glow':'';
    return {avatarClass:`${avatarClass}${frame} ${extra}`, title:c.title||'', vip, glow};
  }
  const PREMIUM_ITEMS=[
    {id:'frame-vip',cat:'Molduras',name:'Moldura VIP',desc:'Brilho dourado exclusivo no seu avatar.',price:490,icon:'👑',kind:'frame'},
    {id:'frame-diamond',cat:'Molduras',name:'Moldura Diamante',desc:'Efeito cristalino de destaque.',price:990,icon:'💎',kind:'frame'},
    {id:'frame-galaxy',cat:'Molduras',name:'Moldura Galáxia',desc:'Visual lendário com brilho cósmico.',price:1490,icon:'🌌',kind:'frame'},
    {id:'effect-electric',cat:'Efeitos',name:'Vitória Elétrica',desc:'Animação especial ao vencer.',price:490,icon:'⚡',kind:'effect'},
    {id:'effect-fire',cat:'Efeitos',name:'Vitória em Chamas',desc:'Explosão visual de fogo na vitória.',price:790,icon:'🔥',kind:'effect'},
    {id:'effect-diamond',cat:'Efeitos',name:'Vitória Diamante',desc:'Efeito raro de cristal.',price:990,icon:'💎',kind:'effect'},
    {id:'title-genius',cat:'Títulos',name:'GÊNIO',desc:'Mostre seu estilo nas partidas.',price:290,icon:'🧠',kind:'title'},
    {id:'title-master',cat:'Títulos',name:'MESTRE',desc:'Título especial para seu perfil.',price:390,icon:'🏆',kind:'title'},
    {id:'title-legend',cat:'Títulos',name:'LENDÁRIO',desc:'Status raro e chamativo.',price:690,icon:'👑',kind:'title'},
    {id:'emoji-troll',cat:'Emojis',name:'Pacote Troll',desc:'😂 😈 💀 👀 🔥 e frases provocadoras.',price:390,icon:'😈',kind:'emoji'},
    {id:'emoji-elite',cat:'Emojis',name:'Pacote Elite',desc:'Reações premium para duelos.',price:490,icon:'😎',kind:'emoji'},
    {id:'avatar-ninja',cat:'Avatares',name:'Avatar Ninja',desc:'Avatar exclusivo para colecionadores.',price:590,icon:'🥷',kind:'avatar'},
    {id:'theme-gold',cat:'Temas',name:'Tema Ouro',desc:'Perfil preto e dourado premium.',price:690,icon:'✨',kind:'theme'},
    {id:'theme-galaxy',cat:'Temas',name:'Tema Galáxia',desc:'Visual cósmico no seu perfil.',price:890,icon:'🌌',kind:'theme'},
    {id:'badge-top1',cat:'Badges',name:'Top 1 Global',desc:'Badge de prestígio para o ranking.',price:0,icon:'🥇',kind:'badge'},
    {id:'vip',cat:'VIP',name:'QuizUp VIP',desc:'Bônus de 25% de XP nas vitórias e identidade premium.',price:9900,icon:'👑',kind:'vip'},
    {id:'pass',cat:'Passe',name:'Passe QuizUp',desc:'Recompensas exclusivas da temporada.',price:1990,icon:'🏆',kind:'pass'},
  ];
  function money(v){return `${Number(v||0).toLocaleString('pt-BR')} ⚡`}
  function itemPurchaseEnabled(item){if(!S.storeSettings?.enabled)return false;return storeCategoryEnabled(item?.cat||'')}
  function storeCategoryEnabled(cat){if(!S.storeSettings?.enabled)return false;if(cat==='VIP')return !!S.storeSettings.vip_enabled;if(cat==='Moedas')return !!S.storeSettings.coins_enabled;if(cat==='Passe')return !!S.storeSettings.pass_enabled;return !!S.storeSettings.cosmetics_enabled}
  async function loadCoinPackages(){if(!sb)return;const {data,error}=await sb.from('coin_packages').select('id,name,coins,price_cents,active,sort_order').eq('active',true).order('sort_order').order('coins');if(!error)S.coinPackages=data||[];}
  async function editCoinPackage(id){if(!sb||!S.isAdmin)return;const x=(S.adminCoinPackages||[]).find(i=>i.id===id);if(!x)return;const coins=prompt('Quantidade de QuizCoins:',String(x.coins));if(coins===null)return;const price=prompt('Preço em reais (ex.: 10.00):',String((Number(x.price_cents||0)/100).toFixed(2)));if(price===null)return;const active=confirm('Deixar este pacote ativo na loja?');const {error}=await sb.from('coin_packages').update({coins:Number(coins),price_cents:Math.round(Number(price.replace(',','.'))*100),active}).eq('id',id);if(error)alert(error.message);else{await loadAdminCoinPackages();await loadCoinPackages();render()}}
  async function loadAdminCoinPackages(){if(!sb||!S.isAdmin)return;const {data,error}=await sb.from('coin_packages').select('id,name,coins,price_cents,active,sort_order').order('sort_order').order('coins');if(!error)S.adminCoinPackages=data||[];}
  async function createCoinPackage(){if(!sb||!S.isAdmin)return;const name=$('#coinPackName')?.value.trim();const coins=Number($('#coinPackCoins')?.value||0);const price=Number(String($('#coinPackPrice')?.value||0).replace(',','.'));if(!name||coins<=0||price<0)return alert('Preencha nome, moedas e preço.');const {error}=await sb.from('coin_packages').insert({name,coins,price_cents:Math.round(price*100),active:true,sort_order:Number($('#coinPackOrder')?.value||0)});if(error)alert(error.message);else{alert('Pacote criado.');$('#coinPackageForm').reset();await loadAdminCoinPackages();await loadCoinPackages();render()}}
  async function loadPremiumItems(){
    if(!sb)return;
    const {data,error}=await sb.from('premium_items').select('id,name,category,description,price_cents,price_coins,promo_price_cents,promo_price_coins,promo_active,promo_expires_at,icon,asset_url,kind,active').eq('active',true).order('created_at',{ascending:false});
    if(!error&&Array.isArray(data)){S.premiumItems=data.map(x=>({id:x.id,cat:x.category,name:x.name,desc:x.description||'',price:Number(x.price_coins??x.price_cents??0),promo_price:Number(x.promo_price_coins??x.promo_price_cents??0),promo_active:!!x.promo_active,promo_expires_at:x.promo_expires_at||null,icon:x.icon||'✨',kind:x.kind||({Molduras:'frame',Efeitos:'effect',Títulos:'title',Emojis:'emoji',Avatares:'avatar',Temas:'theme',Badges:'badge'}[x.category]||'theme'),asset_url:x.asset_url||''}));}
  }
  function premiumDisplayArt(item){return item.asset_url?`<img src="${esc(item.asset_url)}" alt="${esc(item.name)}">`:esc(item.icon||'✨')}
  function premiumCatalog(){return S.premiumItems.length?[...PREMIUM_ITEMS,...S.premiumItems.filter(x=>!PREMIUM_ITEMS.some(y=>y.id===x.id))]:PREMIUM_ITEMS}
  function premiumItemById(id){return premiumCatalog().find(x=>x.id===id)||null}
  function avatarAssetFor(profile){const c=activeCosmeticsFor(profile);const item=premiumItemById(c.avatar);return item?.asset_url||''}
  function profileAvatarMarkup(profile, cls='avatar mini'){const c=activeCosmeticsFor(profile);return av(profile?.username||profile?.display_name||'J',`${cls} premium-frame ${esc(c.frame||'')}`,avatarAssetFor(profile)||profile?.avatar_url||'')}
  function profileIdentityMarkup(profile){const c=activeCosmeticsFor(profile);const badge=esc(premiumItemById(c.badge)?.icon||'');const effect=esc(premiumItemById(c.effect)?.icon||'');return `${c.title?`<span class="premium-mini-title">${esc(c.title)}</span>`:''}${badge?`<span class="premium-mini-badge">${badge}</span>`:''}${effect?`<span class="premium-mini-effect">${effect}</span>`:''}${profile?.premium_vip?'<em class="premium-badge">VIP</em>':''}`}

  async function loadStoreSettings(){if(!sb)return;const {data,error}=await sb.from('premium_store_settings').select('enabled,cosmetics_enabled,vip_enabled,coins_enabled,pass_enabled').eq('id',1).maybeSingle();if(!error&&data)S.storeSettings={...S.storeSettings,...data};}
  function premiumStore(){premiumLoad();if(sb&&!S.premiumItems.length)setTimeout(async()=>{await loadPremiumItems();await loadStoreSettings();render()},0);const cats=['Molduras','Efeitos','Títulos','Emojis','Avatares','Temas','Badges'];const catalog=premiumCatalog();const off=!S.storeSettings?.enabled;return `<section class="premium-store"><div class="premium-store-hero"><div><span>⚡ LOJA</span><h1>Crie sua identidade.</h1><p>Personalize seu perfil e deixe sua marca em cada duelo. Nada aqui muda a jogabilidade.</p>${off?'<div class="store-disabled">🛑 Compras temporariamente desativadas pelo administrador.</div>':''}</div><div class="coin-balance"><b>⚡ ${Number(S.profile?.coins??S.premium.coins??0).toLocaleString('pt-BR')}</b><small>QuizCoins</small><button class="premium-buy-coins" id="buyCoins" ${storeCategoryEnabled('Moedas')?'':'disabled'}>+ COMPRAR MOEDAS</button></div></div><div class="coin-shop-card"><div class="premium-section-head"><b>⚡ COMPRAR QUIZCOINS</b><span>Pagamento em dinheiro • recebe Coins no saldo</span></div><div class="coin-pack-grid">${(S.coinPackages||[]).map(x=>`<article class="coin-pack"><strong>⚡ ${Number(x.coins).toLocaleString('pt-BR')}</strong><span>${esc(x.name||'Pacote de Coins')}</span><b>R$ ${(Number(x.price_cents||0)/100).toFixed(2).replace('.',',')}</b><button class="premium-item-btn" type="button" data-coin-package="${x.id}">COMPRAR</button></article>`).join('')||'<div class="muted">O administrador ainda não cadastrou pacotes.</div>'}</div></div><div class="vip-card"><div><b>👑 QUIZUP VIP</b><h2>Seu perfil, seu estilo.</h2><p>Nome dourado, moldura VIP, reações exclusivas e bônus de XP.</p></div><button class="premium-cta" data-premium-buy="vip" ${storeCategoryEnabled('VIP')?'':'disabled'}>ATIVAR VIP • 9.900 ⚡</button></div><div class="premium-section-head"><b>MAIS VENDIDOS</b><span>Cosméticos • sem vantagem competitiva</span></div><div class="premium-grid">${catalog.slice(0,6).map(premiumCard).join('')}</div><div class="premium-section-head"><b>TODOS OS ITENS</b><span>Escolha uma categoria</span></div><div class="premium-tabs">${cats.map(c=>`<button type="button" data-premium-cat="${esc(c)}">${esc(c)}</button>`).join('')}</div><div class="premium-grid" id="premiumAllGrid">${catalog.map(premiumCard).join('')}</div><div class="premium-pass"><div><span>🏆 TEMPORADA 1</span><h2>PASSE QUIZUP</h2><p>Desbloqueie molduras, emojis, badges e efeitos enquanto joga.</p></div><button class="premium-cta" data-premium-buy="pass" ${storeCategoryEnabled('Passe')?'':'disabled'}>PASSE VIP • 1.990 ⚡</button></div><button class="secondary" id="storeHome">← VOLTAR AO INÍCIO</button></section>`}
  function premiumCard(item){const owned=(S.premium.owned||[]).includes(item.id);const enabled=itemPurchaseEnabled(item);const promo=!!item.promo_active&&(!item.promo_expires_at||new Date(item.promo_expires_at).getTime()>Date.now())&&Number(item.promo_price||0)>0&&Number(item.promo_price)<Number(item.price);const current=promo?Number(item.promo_price):Number(item.price);return `<article class="premium-card ${owned?'owned':''}"><div class="premium-art ${item.kind}">${premiumDisplayArt(item)}</div><div><span class="premium-tag">${esc(item.cat)}</span><h3>${esc(item.name)}</h3><p>${esc(item.desc)}</p><div class="promo-price">${promo?`<s>${money(item.price)}</s> <b>${money(current)}</b>`:`<b>${money(current)}</b>`}</div></div><button class="premium-item-btn" data-premium-buy="${item.id}" ${enabled?'':'disabled'}>${owned?'✓ ATIVO':enabled?money(current):'COMPRAS DESATIVADAS'}</button></article>`}
  async function persistPremiumProfile(){
    if(!sb||!S.user)return;
    const a=premiumActive();
    const vip=(S.premium.owned||[]).includes('vip');
    const payload={coins:Number(S.premium.coins??S.profile?.coins??0),premium_vip:vip,premium_title:a.title||null,premium_frame:a.frame||null,premium_effect:a.effect||null,premium_theme:a.theme||null,premium_avatar:a.avatar||null,premium_badge:a.badge||null};
    const {data,error}=await sb.from('profiles').update(payload).eq('id',S.user.id).select('id,premium_vip,premium_title,premium_frame,premium_effect,premium_theme,premium_avatar,premium_badge').maybeSingle();
    if(!error&&data){S.profile={...S.profile,...data};S.profileDetails=null;}
  }
  async function activateCosmetic(item){
    const current=premiumActive();
    // Apenas um item ativo por slot: moldura, avatar, efeito, tema, título, badge e pacote de emojis.
    S.premium.active={...current,[item.kind]:item.id};
    premiumSave();
    if(sb&&S.user){await sb.from('user_premium_items').upsert({user_id:S.user.id,item_id:item.id,active:true});await sb.rpc('activate_premium_item',{p_item_id:item.id});}
    await persistPremiumProfile();
    render();
  }
  async function premiumBuy(id){
    premiumLoad();
    const item=premiumItemById(id);
    if(!item){return alert('Item não encontrado.')}
    if((S.premium.owned||[]).includes(id)){await activateCosmetic(item);return;}
    if(!itemPurchaseEnabled(item))return alert('Esta compra está temporariamente desativada pelo administrador.');
    const promo=!!item.promo_active&&(!item.promo_expires_at||new Date(item.promo_expires_at).getTime()>Date.now())&&Number(item.promo_price||0)>0&&Number(item.promo_price)<Number(item.price);
    const charge=promo?Number(item.promo_price):Number(item.price);
    if(!sb||!S.user){return alert('Faça login para comprar.')}
    const {data,error}=await sb.rpc('purchase_premium_item',{p_item_id:item.id});
    if(error){return alert(error.message||'Não foi possível concluir a compra.')}
    if(data?.ok===false){return alert(data?.message||'Compra não concluída.')}
    S.premium.coins=Number(data?.balance??data?.new_balance??Math.max(0,Number(S.premium.coins||0)-charge));
    S.profile={...S.profile,coins:S.premium.coins};
    S.premium.owned=[...new Set([...(S.premium.owned||[]),id])];
    if(item.kind==='frame'||item.kind==='avatar'||item.kind==='effect'||item.kind==='theme'||item.kind==='title'||item.kind==='badge'){
      S.premium.active={...S.premium.active,[item.kind]:item.id};
      await sb.rpc('activate_premium_item',{p_item_id:item.id});
      await persistPremiumProfile();
    }else if(item.kind==='vip'){
      S.premium.owned=[...new Set([...(S.premium.owned||[]),'vip'])];
      await persistPremiumProfile();
    }
    await loadPremiumInventory();
    premiumSave();
    alert(`✅ ${item.name} adquirido por ${charge.toLocaleString('pt-BR')} QuizCoins!`);
    render();
  }
  function match(){
    if(S.match&&S.matchCountdown>0){const ids=(S.match.player_ids||[]).filter(id=>id!==S.user.id);const opponent=ids[0]?S.matchPlayers[ids[0]]:S.bot;const name=opponent?.username||opponent?.display_name||'Oponente';return `<div class="classic-match-found"><div class="loading-bolt">ϟ</div><div class="classic-match-label">ADVERSÁRIO ENCONTRADO</div><div class="match-vs"><div class="match-player">${profileAvatarMarkup(S.profile,'avatar huge')}<b class="${S.profile?.premium_vip||S.profile?.premium_title?'premium-name-glow':''}">${esc(S.profile?.username||'Você')} ${S.profile?.premium_vip?'<em class="premium-badge">VIP</em>':''}</b>${premiumItemById(S.profile?.premium_effect||premiumActive().effect)?.icon?`<span class="countdown-cosmetic-effect">${esc(premiumItemById(S.profile?.premium_effect||premiumActive().effect).icon)} efeito</span>`:''}</div><div class="vs-glow">VS</div><div class="match-player">${profileAvatarMarkup(opponent,'avatar huge')}<b class="${opponent?.premium_vip||opponent?.premium_title?'premium-name-glow':''}">${esc(name)} ${opponent?.premium_vip?'<em class="premium-badge">VIP</em>':''}</b>${premiumItemById(opponent?.premium_effect)?.icon?`<span class="countdown-cosmetic-effect">${esc(premiumItemById(opponent?.premium_effect).icon)} efeito</span>`:''}</div></div><div class="countdown-label">Começando em</div><div class="countdown-number">${S.matchCountdown}</div></div>`}
    if(S.match&&S.matchCountdown===0)return `<div class="classic-loading"><div class="loading-bolt">ϟ</div><b>CARREGANDO AS PERGUNTAS</b></div>`;
    const elapsed=Math.floor((Date.now()-(S.searchStartedAt||Date.now()))/1000); if(!S.searching)setTimeout(()=>findMatch(),0);
    if(S.botOffer)return `<div class="classic-loading"><div class="loading-bolt">ϟ</div><h2>Nenhum jogador encontrado</h2><p class="muted">Você pode continuar procurando ou jogar contra o QuizBot.</p><button class="primary" id="playBot">JOGAR CONTRA ROBÔ</button><button class="secondary" id="continueReal">CONTINUAR PROCURANDO</button><button class="secondary" id="cancel">CANCELAR</button></div>`;
    return `<div class="classic-loading"><div class="loading-bolt pulse">ϟ</div><b>PROCURANDO ADVERSÁRIO</b><div class="search-seconds">${elapsed}s</div><div class="muted">Tópico: ${esc(S.category)}</div><div class="queue-avatars">${(S.queueAvatars||[]).slice(0,5).map(p=>av('J','avatar queue-avatar',p.avatar_url||'')).join('')}${(S.queueAvatars||[]).length>5?'<span class="queue-more">•••</span>':''}</div><button class="secondary" id="cancel">CANCELAR</button></div>`;
  }


  async function loadQueueAvatars(){if(!sb||S.route!=='match'||!S.searching)return;const {data}=await sb.rpc('get_queue_avatars',{p_mode:S.mode,p_category:S.category});if(Array.isArray(data)){S.queueAvatars=data;render();}}
  async function findMatch(){
    if(!sb){alert('Supabase não está configurado. Configure o config.js para usar o multiplayer.');return go('login');}
    if(S.searching && S.poll)return;
    S.searching=true;S.botOffer=false;S.searchStartedAt=S.searchStartedAt||Date.now();render();
    clearInterval(S.searchTimer);
    S.searchTimer=setInterval(()=>{if(S.route!=='match'||!S.searching)return;const elapsed=Math.floor((Date.now()-S.searchStartedAt)/1000);if(elapsed>=15){clearInterval(S.searchTimer);clearTimeout(S.poll);S.poll=null;S.botOffer=true;render();}else render()},1000);
    clearInterval(S.queueAvatarsTimer);S.queueAvatarsTimer=setInterval(loadQueueAvatars,1500);loadQueueAvatars();
    const attempt=async()=>{
      if(!S.searching||S.botOffer)return;
      const elapsed=(Date.now()-S.searchStartedAt)/1000;
      if(elapsed>=15){S.botOffer=true;clearInterval(S.searchTimer);S.poll=null;return render()}
      // Cada tentativa envia um heartbeat da fila. Assim, somente jogadores
      // realmente conectados e procurando agora podem formar um match.
      const {data,error}=await sb.rpc('find_or_create_match',{p_mode:S.mode,p_category:S.category});
      if(error){console.error(error);alert(error.message);S.searching=false;return go('categories')}
      if(data){S.searching=false;clearInterval(S.queueAvatarsTimer);S.queueAvatarsTimer=null;await openMatch(data);return}
      S.poll=setTimeout(attempt,1200);
    };
    attempt();
  }
  async function loadMatchPlayers(data){
    const ids=(data.player_ids||[]).filter(id=>id!==S.user.id);
    if(!ids.length)return;
    const {data:rows}=await sb.from('profiles').select('id,username,display_name,avatar_url,premium_vip,premium_frame,premium_effect,premium_theme,premium_avatar,premium_title,premium_badge').in('id',ids);
    const map={};(rows||[]).forEach(x=>map[x.id]=x);S.matchPlayers=map;
  }
  function startMatchCountdown(){
    clearInterval(S.countdownTimer);clearInterval(S.matchSyncTimer);S.matchSyncTimer=null;
    S.matchCountdown=3;sound('match');render();
    let last=3;
    S.countdownTimer=setInterval(async()=>{
      S.matchCountdown--;
      if(S.matchCountdown>0){sound('count');render();return;}
      clearInterval(S.countdownTimer);S.countdownTimer=null;
      if(S.botMode){
        const started=Date.now();
        S.roundStartedAt=started;S.match.state={...(S.match.state||{}),question_started_at:started/1000};
        S.route='game';sound('go');render();startClock();scheduleBotTurn();return;
      }
      if(sb&&S.matchId){
        const {data,error}=await sb.rpc('start_match_round',{p_match_id:S.matchId});
        if(error){console.error(error);return go('categories')}
        if(data){S.match=data;S.questionIndex=Number(data.current_question||0);S.roundStartedAt=Number(data.state?.question_started_at||0)*1000;S.seconds=10;S.answered=false;S.waiting=false;}
      }
      S.route='game';sound('go');render();startClock();
    },1000);
  }
  async function matchPresenceBeat(){if(!sb||!S.matchId||S.botMode||!S.user||!['match','game'].includes(S.route))return;const {data,error}=await sb.rpc('check_match_presence',{p_match_id:S.matchId});if(error){console.warn('presence',error.message);return}if(data?.finished){clearInterval(S.presenceTimer);S.presenceTimer=null;const {data:m}=await sb.from('matches').select('*').eq('id',S.matchId).single();if(m)await syncMatch(m)}}
  function startMatchPresence(){clearInterval(S.presenceTimer);if(!sb||!S.matchId||S.botMode)return;matchPresenceBeat();S.presenceTimer=setInterval(matchPresenceBeat,2000)}
  async function openMatch(id){
    clearTimeout(S.poll);clearInterval(S.searchTimer);S.poll=null;S.searching=false;S.matchId=id;
    const {data,error}=await sb.from('matches').select('*').eq('id',id).single();
    if(error||!data){alert(error?.message||'Não foi possível abrir a partida.');return go('categories')}
    S.match=data;S.asyncMode=false;S.asyncChallengeId=null;S.resultSoundPlayed=false;S.lastCoinsEarned=0;S.rematchMessage='';S.transitionUntil=0;S.transitionQuestion=-1;S.botMode=false;S.bot=null;S.mode=data.mode;S.category=data.category;S.questionIndex=data.current_question||0;S.answered=false;S.waiting=false;S.timeoutInFlight=false;S.lastClockSecond=null;S.clockOffsetMs=0;S.clockSyncKey='';S.clockBaseLocalMs=0;S.clockBaseServerMs=0;S.fiftyUsed=false;S.plusUsed=false;await loadMatchPlayers(data);await loadMatchQuestions();subscribeMatch();S.route='match';startMatchPresence();startMatchCountdown();
  }
  async function loadMatchQuestions(){
    if(!sb||!S.match?.question_ids?.length){alert('A partida não possui perguntas do Supabase. Execute o seed-300-questions.sql.');return go('categories');}
    const {data,error}=await sb.from('questions').select('id,question_text,options,correct_index,image_url').in('id',S.match.question_ids);
    if(error||!data||data.length<7){alert('Esta partida não possui 7 perguntas válidas. Execute o seed-300-questions.sql no Supabase.');return go('categories')}
    const map=new Map(data.map(q=>[q.id,q]));
    // Embaralha as alternativas de forma determinística por pergunta.
    // Assim a correta não fica sempre na letra A, mas os dois jogadores
    // continuam vendo exatamente a mesma ordem de alternativas.
    function shuffleQuestionOptions(q){
      const opts=Array.isArray(q.options)?q.options.slice():[];
      const originalCorrect=Number(q.correct_index);
      if(opts.length<2||!Number.isInteger(originalCorrect)||originalCorrect<0||originalCorrect>=opts.length)return q;
      let seed=0;
      const key=String(q.id||q.question_text||'');
      for(let i=0;i<key.length;i++)seed=(Math.imul(seed,31)+key.charCodeAt(i))|0;
      const order=opts.map((_,i)=>i);
      for(let i=order.length-1;i>0;i--){
        seed=Math.imul(seed^seed>>>16,0x45d9f3b)|0;
        seed=Math.imul(seed^seed>>>16,0x45d9f3b)|0;
        const j=(Math.abs(seed^seed>>>16))%(i+1);
        [order[i],order[j]]=[order[j],order[i]];
      }
      // Evita que, por acaso, a correta continue na posição A.
      if(order.length>1&&order[0]===originalCorrect){
        const j=1+((Math.abs(seed)||1)%(order.length-1));
        [order[0],order[j]]=[order[j],order[0]];
      }
      return {...q,options:order.map(i=>opts[i]),correct_index:order.indexOf(originalCorrect)};
    }
    S.questions=S.match.question_ids.map(id=>map.get(id)).filter(Boolean).map(shuffleQuestionOptions);
  }
  function subscribeMatch(){
    if(!sb||!S.matchId)return;
    if(S.realtime)sb.removeChannel(S.realtime);
    S.matchReactions=[];
    sb.from('match_reactions').select('id,match_id,sender_id,emoji,created_at').eq('match_id',S.matchId).order('created_at',{ascending:false}).limit(10).then(({data})=>{if(Array.isArray(data)){S.matchReactions=data.reverse();render();}});
    S.realtime=sb.channel(`match-${S.matchId}`).on('postgres_changes',{event:'UPDATE',schema:'public',table:'matches',filter:`id=eq.${S.matchId}`},async payload=>{await syncMatch(payload.new)}).on('broadcast',{event:'reaction'},payload=>{const r=payload.payload;if(!r||r.match_id!==S.matchId||r.sender_id===S.user.id)return;if(!S.matchReactions.some(x=>x.id===r.id)){S.matchReactions.push(r);if(S.matchReactions.length>10)S.matchReactions.shift();S.lastReaction=r.emoji||'';render();setTimeout(()=>{S.lastReaction='';render()},1800)}}).on('postgres_changes',{event:'INSERT',schema:'public',table:'match_reactions',filter:`match_id=eq.${S.matchId}`},payload=>{const r=payload.new;if(S.matchReactions.some(x=>x.id===r.id||((x.sender_id===r.sender_id)&&(x.emoji===r.emoji)&&(Date.now()-new Date(x.created_at).getTime()<2200))))return;if(!S.matchReactions.some(x=>x.id===r.id)){S.matchReactions.push(r);if(S.matchReactions.length>6)S.matchReactions.shift();S.lastReaction=r.emoji||'';render();setTimeout(()=>{S.lastReaction='';render()},1800)}}).subscribe();
    clearInterval(S.matchSyncTimer);
    // Realtime é o canal principal; este polling curto é um fallback para garantir
    // que nenhum UPDATE seja perdido e os dois jogadores permaneçam na mesma pergunta.
    S.matchSyncTimer=setInterval(async()=>{
      if(S.route!=='game'||!S.matchId||S.botMode)return;
      const {data}=await sb.from('matches').select('*').eq('id',S.matchId).single();
      if(data)await syncMatch(data);
    },900);
  }
  async function syncMatch(m){
    if(!m||S.botMode)return;
    const serverQuestion=Number(m.current_question||0);
    const localQuestion=Number(S.questionIndex||0);
    if(S.match&&serverQuestion<localQuestion)return;
    const oldStarted=Number(S.match?.state?.question_started_at||0);
    const newStarted=Number(m.state?.question_started_at||0);
    S.match=m;S.mode=m.mode;S.category=m.category;
    if(m.status==='finished'){
      clearInterval(S.timer);clearInterval(S.matchSyncTimer);S.matchSyncTimer=null;
      await finishOnline();return;
    }
    if(serverQuestion>=S.questions.length && m.status!=='finished'){
      if(sb&&S.matchId){await sb.rpc('finalize_match_if_complete',{p_match_id:S.matchId});const {data:finalM}=await sb.from('matches').select('*').eq('id',S.matchId).single();if(finalM&&finalM.status==='finished'){S.match=finalM;await finishOnline();return;}if(finalM)m=finalM;}
      return;
    }
    if(serverQuestion!==localQuestion){
      S.questionIndex=serverQuestion;S.answered=false;S.waiting=false;S.timeoutInFlight=false;S.lastClockSecond=null;S.clockOffsetMs=0;S.clockSyncKey='';S.clockBaseLocalMs=0;S.clockBaseServerMs=0;S.lastAdded=0;S.fiftyUsed=false;S.plusUsed=false;S.timeLimit=10;S.seconds=10;S.roundStartedAt=newStarted*1000;S.transitionUntil=0;S.transitionQuestion=-1;
      S.answerVisual={};
      render();
      if(S.route==='game'&&newStarted>0)startClock();
      return;
    }
    if(newStarted<=0 && S.route==='game' && sb && S.matchId){
      const {data:startedData}=await sb.rpc('start_match_round',{p_match_id:S.matchId});
      const startedAgain=Number(startedData?.state?.question_started_at||0);
      if(startedAgain>0){S.match=startedData;S.roundStartedAt=startedAgain*1000;render();startClock();return;}
    }
    if(newStarted>0 && !S.roundStartedAt)S.roundStartedAt=newStarted*1000;
    const key=`${S.user.id}:${serverQuestion}`;
    S.answered=!!m.answers?.[key] || !!S.answerVisual[key];S.waiting=!!m.answers?.[key];
    if(S.answered)clearInterval(S.timer);else if(newStarted>0 && !S.timer)startClock();
    render();
  }
  function getScore(id){return Number(S.match?.scores?.[id]||0)}
  function totalTeam(team){return(team||[]).reduce((n,id)=>n+getScore(id),0)}
  function myTeam(){return(S.match?.team_a||[]).includes(S.user.id)?S.match.team_a:S.match?.team_b||[S.user.id]}
  function opponentInfo(){const ids=(S.match?.player_ids||[]).filter(id=>id!==S.user.id);const id=ids[0];return id?(S.matchPlayers[id]||{id,username:'Oponente'}):(S.bot||{id:'bot',username:'Robô',display_name:'Robô'});}
  function startQuestionTransition(){clearTimeout(S.questionTransitionTimer);const run=()=>{if(S.route!=='game')return;const left=Math.max(0,S.transitionUntil-Date.now());if(left<=0){S.transitionUntil=0;S.transitionQuestion=-1;render();startClock();return}render();S.questionTransitionTimer=setTimeout(run,250)};run();}
  function asyncOpponent(){const id=(S.match?.player_ids||[]).find(x=>x!==S.user.id);return id?(S.matchPlayers[id]||{id,username:'Amigo'}):{id:'opponent',username:'Amigo'};}
  function asyncProgressOf(id=S.user.id){return Number(S.match?.player_progress?.[id]||0)}
  function asyncAnswerFor(qi=S.questionIndex){return S.match?.answers?.[`${S.user.id}:${qi}`];}
  function asyncGame(){
    const myProgress=asyncProgressOf();
    if(myProgress>=7){return `<div class="classic-loading async-waiting"><div class="loading-bolt">ϟ</div><b>DESAFIO CONCLUÍDO</b><h2>⏳ Aguardando seu amigo</h2><p class="muted">Você terminou suas 7 perguntas. O resultado será liberado quando seu amigo também terminar.</p><div class="async-score-wait">Sua pontuação: <strong>${getScore(S.user.id)}</strong></div><button class="secondary" id="asyncBackFriends">VOLTAR AOS AMIGOS</button></div>`}
    const q=S.questions[myProgress];if(!q)return '<div class="card pad center">Pergunta indisponível.</div>';
    const mine=getScore(S.user.id),opp=asyncOpponent(),rival=getScore(opp.id),myAnswer=asyncAnswerFor(myProgress)||S.answerVisual[`${S.user.id}:${myProgress}`];
    const myPct=Math.min(100,Math.max(0,(mine/160)*100)),oppPct=Math.min(100,Math.max(0,(rival/160)*100));
    const feedback=myAnswer?`<div class="answer-feedback ${myAnswer.correct?'correct':'wrong'}"><strong>${myAnswer.correct?'✓ CORRETO':'✕ ERRADO'}</strong><span>${myAnswer.correct?`+${Number(myAnswer.score||0)} pontos`:'0 pontos'}</span></div>`:'';
    return `<div class="neon-game async-game"><div class="neon-duel-head"><div class="neon-player"><div class="neon-avatar-wrap">${profileAvatarMarkup(S.profile,'avatar neon-avatar')}</div><div class="neon-player-copy"><span>VOCÊ ${premiumBadge()}</span><b>${esc(S.profile?.username||'Você')}</b><small class="premium-game-title">${esc(premiumActive().title||'')}</small><strong>${mine}<small> pts</small></strong></div></div><div class="neon-vs">VS</div><div class="neon-player rival"><div class="neon-player-copy"><span>AMIGO</span><b>${esc(opp.username||'Amigo')}</b><strong>${rival}<small> pts</small></strong></div><div class="neon-avatar-wrap">${profileAvatarMarkup(opp,'avatar neon-avatar')}</div></div></div><div class="neon-progress"><div><i style="width:${myPct}%"></i></div><em></em><div><i style="width:${oppPct}%"></i></div></div><div class="neon-rounds">${Array.from({length:7},(_,i)=>`<span class="${i<myProgress?'done':i===myProgress?'current':''}">${i<myProgress?'✓':i+1}</span>`).join('')}</div><div class="neon-question-card"><div class="neon-question-meta"><span>PERGUNTA ${myProgress+1} DE 7</span><div class="neon-timer" id="tm">${S.seconds}</div></div>${q.image_url?`<img class="neon-question-image" src="${esc(q.image_url)}" alt="">`:''}<p>${esc(q.question_text||'')}</p></div><div class="neon-answers">${(q.options||[]).map((a,i)=>{const selected=myAnswer&&Number(myAnswer.answer)===i;const correct=Number(q.correct_index)===i;const cls=myAnswer&&(correct||selected)?(correct?'answer-correct':selected?'answer-wrong':''):'';return `<button type="button" class="neon-answer ${cls}" data-async-a="${i}" ${S.asyncAnswered?'disabled':''}><span>${'ABCD'[i]}</span><label>${esc(a)}</label>${myAnswer&&correct?'<b>✓</b>':(myAnswer&&selected&&!myAnswer.correct?'<b>✕</b>':'')}</button>`}).join('')}</div>${feedback}${S.asyncAnswered?'<div class="neon-wait">✓ RESPOSTA ENVIADA • AGUARDANDO</div>':''}<div class="async-note">Desafio assíncrono • cada jogador responde no seu ritmo</div></div>`;
  }
  function startAsyncClock(){
    if(S.asyncAnswered||S.route!=='async-game')return;
    const started=Number(S.asyncStartedAt||0)*1000;
    const key=`async:${S.matchId}:${started}`;
    // O polling/realtime pode atualizar a partida várias vezes por segundo.
    // Nunca reinicie o relógio se ele já estiver rodando para esta mesma pergunta.
    if(S.timer && S.clockSyncKey===key)return;
    clearInterval(S.timer);
    const token=++S.clockToken;
    S.lastClockSecond=null;
    if(!Number.isFinite(started)||started<=0){S.seconds=10;const el=$('#tm');if(el)el.textContent='10';return;}
    S.timeLimit=10;
    const tick=()=>{
      if(token!==S.clockToken||S.asyncAnswered||S.route!=='async-game'){clearInterval(S.timer);return;}
      const now=S.clockBaseLocalMs>0 && S.clockBaseServerMs>0
        ? S.clockBaseServerMs+(performance.now()-S.clockBaseLocalMs)
        : Date.now()+Number(S.clockOffsetMs||0);
      const remaining=Math.max(0,10-Math.floor(Math.max(0,now-started)/1000));
      S.seconds=remaining;
      const el=$('#tm');if(el)el.textContent=String(remaining);
      if(S.lastClockSecond!==remaining){S.lastClockSecond=remaining;if(remaining>0&&remaining<=3)sound('count');}
      if(remaining===0){clearInterval(S.timer);if(!S.asyncAnswered&&!S.timeoutInFlight)submitAsyncAnswer(-1);}
    };
    tick();
    S.timer=setInterval(tick,100);
    if(sb&&S.matchId&&S.clockSyncKey!==key){
      S.clockSyncKey=key;
      const before=performance.now();
      sb.rpc('get_match_clock',{p_match_id:S.matchId}).then(({data,error})=>{
        if(error||token!==S.clockToken)return;
        const after=performance.now();
        const serverNow=Number(data?.server_now||0)*1000;
        const serverStarted=Number(data?.question_started_at||0)*1000;
        if(serverNow>0){
          const midpoint=before+(after-before)/2;
          S.clockBaseLocalMs=midpoint;
          S.clockBaseServerMs=serverNow;
          S.clockOffsetMs=serverNow-(performance.timeOrigin+midpoint);
          // No desafio assíncrono o início da pergunta é INDIVIDUAL
          // (player_started_at). Nunca substitua esse timestamp pelo
          // question_started_at da partida ao vivo.
          tick();
        }
      }).catch(()=>{});
    }
  }

  async function openAsyncChallenge(challengeId){
    if(!sb)return alert('Supabase não está configurado.');
    clearInterval(S.searchTimer);clearTimeout(S.poll);S.searching=false;S.asyncMode=true;S.asyncChallengeId=challengeId;
    const {data:c,error:ce}=await sb.from('challenges').select('id,challenger_id,challenged_id,category,status,match_id').eq('id',challengeId).single();
    if(ce||!c||!c.match_id)return alert(ce?.message||'Desafio indisponível.');
    S.matchId=c.match_id;const {data:m,error:me}=await sb.from('matches').select('*').eq('id',c.match_id).single();
    if(me||!m)return alert(me?.message||'Partida do desafio não encontrada.');
    S.match=m;S.mode='1v1';S.category=m.category;S.botMode=false;S.bot=null;S.resultSoundPlayed=false;S.rematchMessage='';S.transitionUntil=0;S.transitionQuestion=-1;S.matchPlayers={};
    S.questionIndex=asyncProgressOf();S.asyncProgress=S.questionIndex;S.asyncAnswered=!!m.answers?.[`${S.user.id}:${S.questionIndex}`];S.answered=S.asyncAnswered;S.waiting=false;S.timeoutInFlight=false;S.clockOffsetMs=0;S.clockSyncKey='';S.clockBaseLocalMs=0;S.clockBaseServerMs=0;S.asyncStartedAt=Number(m.player_started_at?.[S.user.id]||0);await loadMatchPlayers(m);await loadMatchQuestions();
    await startAsyncRound();subscribeAsyncMatch();S.route='async-game';render();if(!S.asyncAnswered&&S.asyncStartedAt)startAsyncClock();
  }
  async function startAsyncRound(){if(!sb||!S.matchId)return;const {data,error}=await sb.rpc('start_async_challenge',{p_match_id:S.matchId});if(error)return alert(error.message);if(data){S.match=data;S.asyncProgress=asyncProgressOf();S.questionIndex=S.asyncProgress;S.asyncStartedAt=Number(data.player_started_at?.[S.user.id]||0);S.asyncAnswered=!!data.answers?.[`${S.user.id}:${S.asyncProgress}`];S.answered=S.asyncAnswered;}}
  function subscribeAsyncMatch(){if(!sb||!S.matchId)return;if(S.realtime)sb.removeChannel(S.realtime);S.realtime=sb.channel(`async-match-${S.matchId}`).on('postgres_changes',{event:'UPDATE',schema:'public',table:'matches',filter:`id=eq.${S.matchId}`},async payload=>syncAsyncMatch(payload.new)).subscribe();clearInterval(S.matchSyncTimer);S.matchSyncTimer=setInterval(async()=>{if(S.route!=='async-game'||!S.matchId)return;const {data}=await sb.from('matches').select('*').eq('id',S.matchId).single();if(data)await syncAsyncMatch(data)},1000)}
  async function syncAsyncMatch(m){
    if(!m||!S.asyncMode)return;
    S.match=m;S.category=m.category;S.mode=m.mode;
    if(m.status==='finished'){
      clearInterval(S.timer);clearInterval(S.matchSyncTimer);S.matchSyncTimer=null;
      if(S.asyncFeedbackUntil>Date.now()){
        clearTimeout(S.asyncAdvanceTimer);S.asyncAdvanceTimer=setTimeout(()=>syncAsyncMatch(m),Math.max(50,S.asyncFeedbackUntil-Date.now()));
        return;
      }
      await finishAsyncOnline();return;
    }
    const progress=asyncProgressOf();
    if(S.asyncFeedbackUntil>Date.now()&&progress!==S.asyncProgress){
      // O outro jogador pode atualizar a partida enquanto mostramos o feedback
      // da resposta local. Não avance a tela do jogador antes do feedback acabar.
      return;
    }
    if(progress!==S.asyncProgress){
      S.asyncProgress=progress;S.questionIndex=progress;S.asyncAnswered=!!m.answers?.[`${S.user.id}:${progress}`];S.answered=S.asyncAnswered;
      S.asyncStartedAt=Number(m.player_started_at?.[S.user.id]||0);S.seconds=10;S.lastClockSecond=null;S.clockSyncKey='';S.clockBaseLocalMs=0;S.clockBaseServerMs=0;render();
      if(!S.asyncAnswered&&S.asyncStartedAt)startAsyncClock();return;
    }
    if(progress<7&&!S.asyncAnswered){
      const started=Number(m.player_started_at?.[S.user.id]||0);
      if(started){S.asyncStartedAt=started;startAsyncClock()}
      else{await startAsyncRound();render();if(S.asyncStartedAt)startAsyncClock()}
    }
  }
  async function submitAsyncAnswer(i){
    if(S.asyncAnswered||S.timeoutInFlight||S.route!=='async-game')return;
    const qi=S.asyncProgress;const q=S.questions[qi];if(!q)return;
    S.asyncAnswered=true;clearInterval(S.timer);S.seconds=i===-1?0:S.seconds;
    const visualKey=`${S.user.id}:${qi}`;const visualCorrect=i>=0&&i===Number(q.correct_index);
    S.answerVisual[visualKey]={answer:i,correct:visualCorrect,score:0};
    if(i===-1)sound('timeout');else sound(visualCorrect?'correct':'wrong');
    render();
    const {data,error}=await sb.rpc('submit_async_challenge_answer',{p_match_id:S.matchId,p_question_index:qi,p_answer_index:i});
    if(error){S.asyncAnswered=false;S.answerVisual[visualKey]={answer:i,correct:visualCorrect,score:0,error:true};render();alert(error.message);return}
    const {data:m}=await sb.from('matches').select('*').eq('id',S.matchId).single();
    if(!m)return;
    S.match=m;
    const serverAnswer=m.answers?.[visualKey];
    S.answerVisual[visualKey]={answer:i,correct:Boolean(serverAnswer?.correct??visualCorrect),score:Number(serverAnswer?.score??data?.added??0),remaining:Number(serverAnswer?.remaining??S.seconds)};
    S.asyncProgress=Number(m.player_progress?.[S.user.id]??(qi+1));
    S.questionIndex=qi;
    S.asyncStartedAt=0;S.clockSyncKey='';S.clockBaseLocalMs=0;S.clockBaseServerMs=0;
    S.asyncFeedbackUntil=Date.now()+1100;
    render();
    clearTimeout(S.asyncAdvanceTimer);
    if(data?.finished||m.status==='finished'){
      S.asyncAdvanceTimer=setTimeout(()=>{if(S.route==='async-game')syncAsyncMatch(m)},1100);
      return;
    }
    S.asyncAdvanceTimer=setTimeout(async()=>{
      if(S.route!=='async-game')return;
      S.asyncFeedbackUntil=0;
      S.asyncProgress=Number(m.player_progress?.[S.user.id]??(qi+1));
      S.questionIndex=S.asyncProgress;S.asyncAnswered=false;delete S.answerVisual[visualKey];
      S.seconds=10;S.lastClockSecond=null;S.clockSyncKey='';S.clockBaseLocalMs=0;S.clockBaseServerMs=0;
      render();await startAsyncRound();render();if(S.asyncStartedAt)startAsyncClock();
    },1100);
  }
  async function finishAsyncOnline(){if(S.route==='result')return;const mine=getScore(S.user.id);const opp=(S.match?.player_ids||[]).find(x=>x!==S.user.id);const oppScore=getScore(opp);const outcome=mine===oppScore?'draw':mine>oppScore?'win':'loss';const win=outcome==='win';if(sb){const {data:existing}=await sb.from('game_results').select('id').eq('match_id',S.matchId).eq('user_id',S.user.id).maybeSingle();if(!existing){await sb.from('game_results').insert({user_id:S.user.id,category:S.category,mode:'1v1',score:mine,won:win,outcome,match_id:S.matchId});if(outcome!=='draw'){const vip=!!S.profile?.premium_vip||!!S.premium?.owned?.includes('vip');const xpScore=vip?Math.round(mine*1.25):mine;await sb.rpc('apply_game_result',{p_user_id:S.user.id,p_category:S.category,p_score:xpScore,p_won:win});};const reward=await sb.rpc('award_match_coins',{p_match_id:S.matchId});if(!reward.error&&reward.data){S.lastCoinsEarned=Number(reward.data.coins_earned||0);S.premium.coins=Number(reward.data.coins_balance??S.premium.coins);S.profile={...S.profile,coins:S.premium.coins};}await loadProfile();await loadPremiumInventory()}}S.myScore=mine;S.rankRows=null;S.profileDetails=null;S.route='result';render()}

  function game(){
    if(S.transitionUntil>Date.now()){const n=Math.max(1,Math.ceil((S.transitionUntil-Date.now())/1000));return `<div class="classic-round-transition"><div class="loading-bolt">ϟ</div><b>RODADA ${S.questionIndex+1}</b><strong>${n}</strong></div>`}
    const q=S.questions[S.questionIndex];if(!q)return '<div class="card pad center"><h2>Pergunta indisponível</h2></div>';
    const mine=getScore(S.user.id),opp=opponentInfo(),rival=getScore(opp.id),progress=S.questionIndex+1;
    const answerMap=S.match?.answers||{},myAnswer=answerMap[`${S.user.id}:${S.questionIndex}`]||S.answerVisual[`${S.user.id}:${S.questionIndex}`];
    const pctMe=Math.min(100,Math.max(0,(mine/160)*100)),pctOpp=Math.min(100,Math.max(0,(rival/160)*100));
    const answeredNow=!!myAnswer||S.answered||S.waiting;
    const feedback=myAnswer ? `<div class="answer-feedback ${myAnswer.correct?'correct':'wrong'}"><strong>${myAnswer.correct?'✓ CORRETO':'✕ ERRADO'}</strong><span>${myAnswer.correct?`+${Number(myAnswer.score||0)} pontos`:'0 pontos'}</span></div>` : '';
    const reactions=(S.matchReactions||[]).slice(-4).map(r=>`<span class="match-reaction ${r.sender_id===S.user.id?'mine':''}">${esc(r.emoji||'🙂')}</span>`).join('');
    const reactionPicker=S.emojiOpen?`<div class="match-emoji-picker">${['😂','😎','😏','🤔','😱','🔥','👏','💪','😈','😭','🤣','🎯','💀','❤️','👀'].map(e=>`<button type="button" class="match-emoji" data-match-emoji="${e}">${e}</button>`).join('')}</div>`:'';
    const myReaction=[...(S.matchReactions||[])].reverse().find(r=>r.sender_id===S.user.id); const oppReaction=[...(S.matchReactions||[])].reverse().find(r=>r.sender_id!==S.user.id);
    return `<div class="neon-game"><div class="neon-duel-head"><div class="neon-player"><div class="neon-avatar-wrap">${profileAvatarMarkup(S.profile,'avatar neon-avatar')}${myReaction?`<span class="avatar-reaction-bubble mine">${esc(myReaction.emoji)}</span>`:''}</div><div class="neon-player-copy"><span>VOCÊ ${premiumBadge()}</span><b>${esc(S.profile?.username||'Você')}</b><small class="premium-game-title">${esc(premiumActive().title||'')}</small><strong>${mine}<small> pts</small></strong></div></div><div class="neon-vs">VS</div><div class="neon-player rival"><div class="neon-player-copy"><span>OPONENTE</span><b>${esc(opp.username||'Oponente')}</b><strong>${rival}<small> pts</small></strong></div><div class="neon-avatar-wrap">${profileAvatarMarkup(opp,'avatar neon-avatar')}${oppReaction?`<span class="avatar-reaction-bubble opponent">${esc(oppReaction.emoji)}</span>`:''}</div></div></div><div class="neon-progress"><div><i style="width:${pctMe}%"></i></div><em></em><div><i style="width:${pctOpp}%"></i></div></div><div class="neon-rounds">${Array.from({length:7},(_,i)=>`<span class="${i< S.questionIndex?'done':i===S.questionIndex?'current':''}">${i<S.questionIndex?'✓':i+1}</span>`).join('')}</div><div class="neon-question-card"><div class="neon-question-meta"><span>PERGUNTA ${progress} DE 7</span><div class="neon-timer" id="tm">${S.seconds}</div></div>${q.image_url?`<img class="neon-question-image" src="${esc(q.image_url)}" alt="">`:''}<p>${esc(q.question_text||'')}</p></div><div class="neon-answers">${(q.options||[]).map((a,i)=>{const selected=myAnswer&&Number(myAnswer.answer)===i;const isCorrect=Number(q.correct_index)===i;const cls=answeredNow&&isCorrect?'answer-correct':(selected&&!myAnswer?.correct?'answer-wrong':(selected?'selected':''));return `<button type="button" class="neon-answer ${cls}" data-a="${i}" ${answeredNow?'disabled':''}><span>${'ABCD'[i]}</span><label>${esc(a)}</label>${answeredNow&&isCorrect?'<b>✓</b>':(selected&&!myAnswer?.correct?'<b>✕</b>':'')}</button>`}).join('')}</div>${feedback}${S.waiting?'<div class="neon-wait">✓ RESPOSTA ENVIADA • AGUARDANDO O OPONENTE</div>':''}<div class="match-reaction-bar"><button type="button" id="matchEmojiBtn" class="match-emoji-open">😊 Reagir</button></div>${reactionPicker}</div>`;
  }


  function startClock(){
    clearInterval(S.timer);
    const token=++S.clockToken;
    S.lastClockSecond=null;
    if(S.answered||S.waiting||S.route!=='game')return;
    const started=Number(S.roundStartedAt||Number(S.match?.state?.question_started_at||0)*1000);
    if(!Number.isFinite(started)||started<=0){S.seconds=10;const el=$('#tm');if(el)el.textContent='10';return;}
    S.roundStartedAt=started;S.timeLimit=10;
    const key=`live:${S.matchId||'local'}:${started}`;
    const tick=()=>{
      if(token!==S.clockToken||S.answered||S.waiting||S.route!=='game'){clearInterval(S.timer);return;}
      const now=S.clockBaseLocalMs>0 && S.clockBaseServerMs>0
        ? S.clockBaseServerMs+(performance.now()-S.clockBaseLocalMs)
        : Date.now()+Number(S.clockOffsetMs||0);
      const elapsed=Math.max(0,now-started);
      const remaining=Math.max(0,10-Math.floor(elapsed/1000));
      S.seconds=remaining;
      const el=$('#tm');if(el)el.textContent=String(remaining);
      if(S.lastClockSecond!==remaining){
        S.lastClockSecond=remaining;
        if(remaining>0&&remaining<=3)sound('count');
      }
      if(remaining===0){clearInterval(S.timer);if(!S.answered&&!S.waiting&&!S.timeoutInFlight)timeoutRound();}
    };
    tick();
    S.timer=setInterval(tick,100);
    if(sb&&S.matchId&&S.clockSyncKey!==key){
      S.clockSyncKey=key;
      const before=performance.now();
      sb.rpc('get_match_clock',{p_match_id:S.matchId}).then(({data,error})=>{
        if(error||token!==S.clockToken)return;
        const after=performance.now();
        const serverNow=Number(data?.server_now||0)*1000;
        const serverStarted=Number(data?.question_started_at||0)*1000;
        if(serverNow>0){
          const midpoint=before+(after-before)/2;
          S.clockBaseLocalMs=midpoint;
          S.clockBaseServerMs=serverNow;
          S.clockOffsetMs=serverNow-(performance.timeOrigin+midpoint);
          if(serverStarted>0&&Math.abs(serverStarted-started)>50){S.roundStartedAt=serverStarted;}
          tick();
        }
      }).catch(()=>{});
    }
  }

  async function timeoutRound(){
    if(S.answered||S.waiting||S.timeoutInFlight||S.route!=='game')return;
    S.timeoutInFlight=true;S.answered=true;S.seconds=0;clearInterval(S.timer);sound('timeout');
    const qi=S.questionIndex;
    const key=`${S.user.id}:${qi}`;
    // Visual state immediately, including a zero-point result.
    S.answerVisual[key]={answer:-1,correct:false,score:0,remaining:0};S.match={...S.match,answers:{...(S.match?.answers||{}),[key]:{answer:-1,correct:false,score:0,remaining:0}}};
    render();
    // Contra o robô não existe RPC/partida no Supabase. O timeout precisa apenas
    // registrar a resposta localmente e liberar a vez do robô para a rodada avançar.
    if(S.botMode){
      S.timeoutInFlight=false;
      setTimeout(()=>{if(S.botMode&&S.route==='game'&&S.match?.answers?.[`${S.bot.id}:${qi}`])maybeAdvanceBotRound();else if(S.botMode&&S.route==='game')botAnswer()},350);
      return;
    }
    if(!sb||!S.matchId){S.timeoutInFlight=false;return;}
    const {data,error}=await sb.rpc('submit_match_answer',{p_match_id:S.matchId,p_question_index:qi,p_answer_index:-1,p_seconds:0});
    S.timeoutInFlight=false;
    if(error){
      S.answered=false;
      delete (S.match?.answers||{})[key];
      const {data:m}=await sb.from('matches').select('*').eq('id',S.matchId).single();
      if(m)await syncMatch(m);
      return;
    }
    if(data?.resync||data?.finished||data?.next_question!==undefined){
      const {data:m}=await sb.from('matches').select('*').eq('id',S.matchId).single();
      if(m)await syncMatch(m);
      return;
    }
    S.waiting=true;render();
  }
  async function answer(i){
    if(S.answered||S.waiting)return;
    if(i<0){timeoutRound();return;}
    S.answered=true;clearInterval(S.timer);
    const seconds=Math.max(0,S.seconds);
    const currentQ=S.questions[S.questionIndex];
    if(i>=0 && currentQ){const visualKey=`${S.user.id}:${S.questionIndex}`;const correct=i===Number(currentQ.correct_index);sound(correct?'correct':'wrong');S.answerVisual[visualKey]={answer:i,correct,score:0};S.match={...S.match,answers:{...(S.match.answers||{}),[visualKey]:{answer:i,correct,score:0}}};render()}
    if(S.botMode){
      const q=S.questions[S.questionIndex];const correct=i===Number(q.correct_index);const remaining=Math.min(Math.max(seconds,0),10);const added=correct?(S.questionIndex===6?20+remaining*2:10+remaining):0;const myKey=`${S.user.id}:${S.questionIndex}`;S.match.scores[S.user.id]=getScore(S.user.id)+added;S.match.answers[myKey]={answer:i,correct,score:added};S.lastAdded=added;render();
      if(S.match.answers?.[`${S.bot.id}:${S.questionIndex}`]){setTimeout(maybeAdvanceBotRound,700)}else scheduleBotTurn();return;
    }
    if(!sb){delete (S.match?.answers||{})[`${S.user.id}:${S.questionIndex}`];S.answered=false;alert('Supabase não está configurado. Configure o config.js.');return go('login')}
    // Confirma o estado atual no servidor antes de enviar a resposta.
    const {data:latest,error:latestError}=await sb.from('matches').select('*').eq('id',S.matchId).single();
    if(latestError||!latest){delete (S.match?.answers||{})[`${S.user.id}:${S.questionIndex}`];S.answered=false;render();startClock();return alert(latestError?.message||'Não foi possível sincronizar a partida.')}
    if(latest.status==='finished'||Number(latest.current_question||0)!==Number(S.questionIndex||0)){
      await syncMatch(latest);return;
    }
    const {data,error}=await sb.rpc('submit_match_answer',{p_match_id:S.matchId,p_question_index:S.questionIndex,p_answer_index:i,p_seconds:seconds});
    if(!error&&S.questionIndex>=S.questions.length-1){await sb.rpc('finalize_match_if_complete',{p_match_id:S.matchId});}
    if(error){
      // O servidor não deve mais exibir o alerta "question out of sync"; ainda assim,
      // se uma versão antiga da função RPC estiver instalada, sincronizamos silenciosamente.
      const msg=String(error.message||'');
      if(/question out of sync|match is not playing/i.test(msg)){
        delete (S.match?.answers||{})[`${S.user.id}:${S.questionIndex}`];
        const {data:m}=await sb.from('matches').select('*').eq('id',S.matchId).single();
        if(m){S.answered=false;await syncMatch(m);return}
      }
      delete (S.match?.answers||{})[`${S.user.id}:${S.questionIndex}`];S.answered=false;render();alert(msg);startClock();return;
    }
    S.timeoutInFlight=false;
    let added=Number(data?.added ?? data?.points_added ?? data?.score_added ?? data?.points ?? NaN);
    if(!Number.isFinite(added)){const isCorrect=i===Number(currentQ?.correct_index);added=isCorrect?(S.questionIndex===6?20+seconds*2:10+seconds):0;}
    S.lastAdded=added;
    if(data?.scores)S.match={...S.match,scores:data.scores};
    if(data?.answers)S.match={...S.match,answers:data.answers};
    if(data?.resync||data?.finished){const {data:m}=await sb.from('matches').select('*').eq('id',S.matchId).single();if(m)await syncMatch(m);return}
    const visualKey=`${S.user.id}:${S.questionIndex}`;
    S.waiting=true;S.match={...S.match,answers:{...(S.match.answers||{}),[visualKey]:{answer:i,correct:i===Number(currentQ?.correct_index),score:data?.added||0}}};
    S.answerVisual[visualKey]={answer:i,correct:i===Number(currentQ?.correct_index),score:data?.added||0};
    clearInterval(S.timer);
    const {data:fresh}=await sb.from('matches').select('*').eq('id',S.matchId).single();
    if(fresh){S.match=fresh;S.myScore=Number(fresh.scores?.[S.user.id]||0);if(fresh.status==='finished'){await finishOnline();return;}}
    render()
  }
  function scheduleBotTurn(){if(!S.botMode||S.route!=='game'||S.answered||S.waiting)return;clearTimeout(S.botTurnTimer);const wait=1800+Math.random()*6500;S.botTurnTimer=setTimeout(()=>{if(S.transitionUntil>Date.now()){S.botTurnTimer=setTimeout(scheduleBotTurn,Math.max(250,S.transitionUntil-Date.now()+100));return}if(S.botMode&&S.route==='game'&&!S.match.answers?.[`${S.bot.id}:${S.questionIndex}`])botAnswer()},wait)}
  function maybeAdvanceBotRound(){if(!S.botMode||!S.match)return;const myKey=`${S.user.id}:${S.questionIndex}`;const botKey=`${S.bot.id}:${S.questionIndex}`;if(!S.match.answers?.[myKey]||!S.match.answers?.[botKey])return;if(S.questionIndex>=S.questions.length-1){finishBot();return}const next=S.questionIndex+1;S.questionIndex=next;S.match.current_question=next;S.match.state={...(S.match.state||{}),question_started_at:Date.now()/1000};S.roundStartedAt=Date.now();S.transitionUntil=0;S.transitionQuestion=-1;S.answered=false;S.waiting=false;S.fiftyUsed=false;S.plusUsed=false;S.timeLimit=10;S.seconds=10;S.lastAdded=0;S.answerVisual={};render();startClock();scheduleBotTurn()}
  function botAnswer(){
    if(!S.botMode||S.route!=='game'||!S.match||S.transitionUntil>Date.now())return;
    const q=S.questions[S.questionIndex];if(!q)return;
    const key=`${S.bot.id}:${S.questionIndex}`;if(S.match.answers?.[key]){maybeAdvanceBotRound();return}
    const botId=S.bot.id;const correct=Math.random()<0.72;const answer=correct?Number(q.correct_index):[0,1,2,3].filter(x=>x!==Number(q.correct_index))[Math.floor(Math.random()*3)];const botSeconds=correct?(2+Math.floor(Math.random()*8)):10;const botRemaining=Math.min(Math.max(10-botSeconds,0),10);const added=correct?(S.questionIndex===6?20+botRemaining*2:10+botRemaining):0;
    S.match.scores[botId]=getScore(botId)+added;S.match.answers[key]={answer,correct,score:added};
    if(S.answered){S.waiting=false;render();setTimeout(maybeAdvanceBotRound,700)}else{render();}
  }
  async function startBotMatch(){
    clearTimeout(S.poll);S.poll=null;clearInterval(S.searchTimer);if(sb)await sb.rpc('cancel_match_queue');
    const {data,error}=await sb.from('questions').select('id,question_text,options,correct_index,image_url').eq('active',true).eq('approval_status','approved').eq('category_name',S.category).limit(50);
    if(error||!data||data.length<7){return alert('Esta categoria ainda não possui 7 perguntas ativas.')}
    const questions=[...data].sort(()=>Math.random()-.5).slice(0,7);const botId='00000000-0000-0000-0000-000000000001';S.bot={id:botId,username:'QuizBot',display_name:'QuizBot',avatar_url:''};S.botMode=true;S.mode='1v1';S.searching=false;S.botOffer=false;S.questions=questions;S.resultSoundPlayed=false;S.match={id:null,mode:'1v1',category:S.category,player_ids:[S.user.id,botId],team_a:[S.user.id],team_b:[botId],scores:{[S.user.id]:0,[botId]:0},answers:{},state:{question_started_at:null},status:'playing',current_question:0,question_ids:questions.map(q=>q.id)};S.matchPlayers={[botId]:S.bot};S.questionIndex=0;S.answered=false;S.waiting=false;startMatchCountdown();
  }
  async function finishBot(){
    clearInterval(S.timer);const mine=getScore(S.user.id),botScore=getScore(S.bot.id),win=mine>botScore;S.myScore=mine;S.match.status='finished';
    // Partidas contra robô não geram XP, vitórias ou derrotas no ranking.
    S.myScore=mine;
    S.route='result';render();
  }
  async function finishOnline(){if(S.route==='result')return;const mine=getScore(S.user.id);const teamA=totalTeam(S.match.team_a),teamB=totalTeam(S.match.team_b);const rivalScore=S.mode==='2v2'?(S.match.team_a.includes(S.user.id)?teamB:teamA):Math.max(...S.match.player_ids.filter(x=>x!==S.user.id).map(getScore),0);const outcome=mine===rivalScore?'draw':mine>rivalScore?'win':'loss';const win=outcome==='win';if(sb){const {data:existing}=await sb.from('game_results').select('id').eq('match_id',S.matchId).eq('user_id',S.user.id).maybeSingle();if(!existing){await sb.from('game_results').insert({user_id:S.user.id,category:S.category,mode:S.mode,score:mine,won:win,outcome,match_id:S.matchId});if(outcome!=='draw'){const vip=!!S.profile?.premium_vip||!!S.premium?.owned?.includes('vip');const xpScore=vip?Math.round(mine*1.25):mine;await sb.rpc('apply_game_result',{p_user_id:S.user.id,p_category:S.category,p_score:xpScore,p_won:win});};const reward=await sb.rpc('award_match_coins',{p_match_id:S.matchId});if(!reward.error&&reward.data){S.lastCoinsEarned=Number(reward.data.coins_earned||0);S.premium.coins=Number(reward.data.coins_balance??S.premium.coins);S.profile={...S.profile,coins:S.premium.coins};}await loadProfile();await loadPremiumInventory();}}S.myScore=mine;S.rankRows=null;S.profileDetails=null;S.route='result';render()}
  function startResultPresence(){clearInterval(S.resultPresenceTimer);if(!sb||!S.matchId||S.botMode)return;const beat=async()=>{if(S.route!=='result'||!S.matchId)return;const {data}=await sb.rpc('heartbeat_result_presence',{p_match_id:S.matchId});if(data?.rematch_match_id){clearInterval(S.resultPresenceTimer);S.resultPresenceTimer=null;await openMatch(data.rematch_match_id)}};beat();S.resultPresenceTimer=setInterval(beat,2000)}
  async function requestRematch(){if(!sb||!S.matchId||S.botMode)return;S.rematchMessage='';render();const {data,error}=await sb.rpc('rematch_match',{p_match_id:S.matchId});if(error){S.rematchMessage=error.message;render();return}if(data?.ok&&data.match_id){clearInterval(S.resultPresenceTimer);S.resultPresenceTimer=null;await openMatch(data.match_id);return}S.rematchMessage='Oponente se retirou da sala.';render()}
  function result(){
    const mine=getScore(S.user.id)||S.myScore;const opponents=(S.match?.player_ids||[]).filter(x=>x!==S.user.id);const opp=opponents[0]?S.matchPlayers[opponents[0]]:(S.bot||{});const oppScore=S.mode==='2v2'?((S.match?.team_a||[]).includes(S.user.id)?totalTeam(S.match.team_b):totalTeam(S.match.team_a)):(opponents[0]?getScore(opponents[0]):getScore(S.bot?.id));const outcome=mine===oppScore?'draw':mine>oppScore?'win':'loss',win=outcome==='win',perfect=mine===160;if(!S.resultSoundPlayed){sound(outcome==='win'?'win':outcome==='draw'?'match':'lose');S.resultSoundPlayed=true}if(sb&&S.matchId&&!S.botMode&&!S.resultPresenceTimer)setTimeout(startResultPresence,0);
    const chart=detailChart();
    return `<div class="classic-result"><div class="result-kicker">RESULTADOS</div><h1>${outcome==='win'?'VITÓRIA':outcome==='draw'?'EMPATE':'DERROTA'}</h1><div class="result-players"><div>${profileAvatarMarkup(S.profile,'avatar big')}<b>${esc(S.profile?.username||'Você')}</b><div class="premium-game-identity">${profileIdentityMarkup(S.profile)}</div><strong class="${win?'green':'red'}">${mine}</strong></div><span>VS</span><div>${profileAvatarMarkup(opp,'avatar big')}<b>${esc(opp?.username||'Oponente')}</b><div class="premium-game-identity">${profileIdentityMarkup(opp)}</div><strong class="${outcome==='draw'?'yellow':'red'}">${oppScore}</strong></div></div><div class="result-metrics"><div><b>${mine}</b><small>PONTUAÇÃO</small></div><div><b>${S.match?.answers?Object.values(S.match.answers).filter(x=>x&&x.score).length:0}</b><small>RESPOSTAS</small></div><div><b>${perfect?'160':'+'+mine}</b><small>XP DA PARTIDA</small></div></div>${perfect?'<div class="perfect-score">🏆 PONTUAÇÃO PERFEITA!</div>':''}<div class="classic-xp"><div class="xp-circle"><span>XP</span><b>${S.botMode?'+0':'+'+mine}</b></div><div><b>${S.botMode?'Partida contra robô':'Experiência conquistada'}</b><small>${outcome==='win'?(S.profile?.premium_vip?'Vitória + bônus VIP de 25% no XP.':'Você venceu este confronto.') :outcome==='draw'?'Os dois terminaram com a mesma pontuação.':'Continue jogando para subir no ranking.'}</small></div></div>${!S.botMode&&S.lastCoinsEarned>0?`<div class="coins-earned-result">⚡ +${Number(S.lastCoinsEarned).toLocaleString('pt-BR')} QuizCoins${outcome==='win'?' • bônus de vitória +25%':''}</div>`:''}<div class="result-detail"><b>DETALHES</b>${chart}</div><div class="result-actions">${!S.botMode&&opponents.length?`<button class="result-btn play" id="rematch">Jogar</button><button class="result-btn chat" id="resultChat">Chat</button><button class="result-btn publish" id="publishResult">Publicar</button>`:''}<button class="secondary" id="again">JOGAR OUTRA</button><button class="secondary" id="home">VOLTAR AO INÍCIO</button>${S.rematchMessage?`<div class="notice center rematch-notice">${esc(S.rematchMessage)}</div><button class="secondary" id="findAnother">PROCURAR OUTRO</button>`:''}</div></div>`;
  }
  function detailChart(){const ids=[S.user.id,...((S.match?.player_ids||[]).filter(x=>x!==S.user.id).slice(0,1))];const pts=ids.map(id=>{let total=0;return Array.from({length:7},(_,i)=>{const a=S.match?.answers?.[`${id}:${i}`];total+=Number(a?.score||0);return total})});const max=160;const make=(arr)=>arr.map((v,i)=>`${20+i*50},${150-(v/max*120)}`).join(' ');return `<svg class="score-chart" viewBox="0 0 340 175" role="img"><line x1="20" y1="150" x2="320" y2="150"/><line x1="20" y1="30" x2="20" y2="150"/><polyline points="${make(pts[0]||[])}"/><polyline class="rival-line" points="${make(pts[1]||[])}"/><text x="20" y="168">1</text><text x="70" y="168">2</text><text x="120" y="168">3</text><text x="170" y="168">4</text><text x="220" y="168">5</text><text x="270" y="168">6</text><text x="315" y="168">7</text></svg>`}


  function rank(){if(!S.rankRows){setTimeout(loadRanking,0);return `<section class="classic-page"><div class="classic-banner"><b>Ranking</b><span>Veja quem está dominando cada tópico.</span></div><div class="card pad center">Carregando ranking...</div></section>`}const rows=S.rankRows||[];const selected=S.rankCategory;return `<section class="classic-page"><div class="classic-section-head"><b>Ranking Global de XP</b><span class="muted">${selected==='__global__'?'XP acumulado':esc(selected)}</span></div><select id="rankCategory" class="classic-select"><option value="__global__" ${selected==='__global__'?'selected':''}>Ranking Global de XP</option>${(S.categories||[]).map(c=>`<option value="${esc(c.name)}" ${selected===c.name?'selected':''}>${esc(c.name)}</option>`).join('')}</select><div class="tabs classic-tabs"><button class="on">Esta temporada</button><button>Todos</button><button>Amigos</button></div><div class="podium">${rows.slice(0,3).map((r,i)=>`<button class="podium-card p${i+1}" data-profile="${r.id}"><span>${['🥇','🥈','🥉'][i]}</span>${profileAvatarMarkup(r,'avatar mini')}<b>${esc(r.username||r.display_name||'Jogador')}</b><div class="premium-game-identity">${profileIdentityMarkup(r)}</div><small>${selected==='__global__'?(r.xp||0)+' XP':'Nível '+(r.level||1)}</small></button>`).join('')}</div><div class="list">${rows.slice(3).map((r,i)=>`<button class="row player-row ${r.id===S.user.id?'me':''}" data-profile="${r.id}"><b>#${i+4}</b>${profileAvatarMarkup(r,'avatar mini')}<div><b>${esc(r.username||r.display_name||'Jogador')}</b><div class="muted">Nível ${r.level||1} • ${r.wins||0} vitórias</div></div><strong>${selected==='__global__'?(r.xp||0)+' XP':(r.topic_xp||0)+' XP'}</strong></button>`).join('')}</div></section>`}
  async function loadRanking(){if(!sb)return;if(S.rankCategory&&S.rankCategory!=='__global__'){const {data,error}=await sb.rpc('get_topic_ranking',{p_category:S.rankCategory,p_limit:100});if(error)return alert(error.message);S.rankRows=data||[];render();return}const {data,error}=await sb.from('profiles').select('id,username,display_name,avatar_url,xp,wins,losses,draws,level,premium_vip,premium_frame,premium_effect,premium_theme,premium_avatar,premium_title,premium_badge').order('xp',{ascending:false}).limit(100);if(error)return alert(error.message);S.rankRows=data||[];render()}

  function profile(){
    if(!S.recentRows)setTimeout(loadRecentResults,0);
    const id=S.profileTargetId||S.user.id;
    if(!S.profileDetails||S.profileDetails.id!==id){setTimeout(()=>loadProfileDetails(id),0);return `<section class="classic-page"><div class="card pad center">Carregando perfil...</div></section>`}
    const p=S.profileDetails,mine=id===S.user.id;
    const topics=(S.recentRows||[]).filter(r=>r&&r.category).reduce((a,r)=>{a[r.category]=(a[r.category]||0)+Number(r.score||0);return a},{});
    const topTopics=Object.entries(topics).sort((a,b)=>b[1]-a[1]).slice(0,6);
    const c=activeCosmeticsFor(p);const avatarUrl=avatarAssetFor(p);
    const inv=mine?`<div class="inventory-section"><div class="classic-section-head"><b>🎒 Meu inventário</b><span>${S.inventoryItems.length} itens</span></div><div class="inventory-grid">${S.inventoryItems.length?S.inventoryItems.map(item=>`<article class="inventory-card ${item.activeOwned?'active':''}"><div class="inventory-art">${premiumDisplayArt(item)}</div><div><b>${esc(item.name)}</b><small>${esc(item.category)}</small></div><button type="button" class="use-inventory ${item.activeOwned?'active':''}" data-use-premium="${esc(item.id)}">${item.activeOwned?'✓ USANDO':'USAR'}</button></article>`).join(''):'<div class="classic-empty">Você ainda não comprou itens.</div>'}</div></div>`:'';
    return `<section class="classic-profile ${p.premium_theme?'premium-theme-'+esc(p.premium_theme):''}"><div class="profile-cover"><div class="profile-avatar-stage">${av(p.username||'J',`avatar profile-avatar premium-frame ${esc(c.frame||'')}`,avatarUrl||p.avatar_url||'')}${c.effect?`<span class="profile-effect-badge">${esc(premiumItemById(c.effect)?.icon||'✨')}</span>`:''}</div><h1 class="${p.premium_vip||p.premium_title?'premium-name-glow':''}">${esc(p.username||p.display_name)} ${p.premium_vip?'<em class="premium-badge">VIP</em>':''}</h1><p>${esc(c.title||'')} ${c.title?'• ':''}Nível ${p.level||1} • ${p.xp||0} XP</p><div class="profile-coins">⚡ ${Number(p.coins||0).toLocaleString('pt-BR')} QuizCoins</div><div class="profile-numbers"><span><b>${p.games||0}</b>JOGOS</span><span><b>${p.wins||0}</b>VITÓRIAS</span><span><b>${p.losses||0}</b>DERROTAS</span><span><b>${p.draws||0}</b>EMPATES</span></div></div><div class="premium-profile-strip"><div><span>${esc(premiumItemById(c.badge)?.icon||'👑')}</span><b>${esc(c.title||'Jogador')}</b><small>${p.premium_vip?'QuizUp VIP • +25% XP nas vitórias':'Identidade especial'}</small></div>${mine?'<button class="premium-mini-btn" id="profileStore">🛒 Loja</button>':''}</div>${mine?'<label class="photo-btn profile-photo-action" for="avatarFile">📷 Alterar foto</label><input id="avatarFile" type="file" accept="image/*" class="hidden">':''}${inv}<div class="classic-section-head"><b>Meus tópicos</b><span>Mais jogados</span></div><div class="profile-topic-list">${topTopics.map(([name,xp])=>`<button data-topic="${esc(name)}"><span>✦</span><div><b>${esc(name)}</b><small>Nível ${Math.max(1,1+Math.floor(xp/1000))}</small></div><strong>${xp} XP</strong></button>`).join('')||'<div class="classic-empty">Jogue para construir seu perfil por tópico.</div>'}</div><div class="profile-grid classic-profile-grid"><div><span>Partidas</span><b>${p.games||0}</b></div><div><span>Vitórias</span><b>${p.wins||0}</b></div><div><span>Derrotas</span><b>${p.losses||0}</b></div><div><span>Empates</span><b>${p.draws||0}</b></div><div><span>Taxa de vitória</span><b>${p.accuracy||0}%</b></div></div>${mine?'<button class="secondary" id="friendsBtn">♧ MEUS AMIGOS</button><button class="secondary" id="logoutProfile">🚪 SAIR DA CONTA</button>':'<button class="secondary" id="backRank">← VOLTAR AO RANKING</button>'}</section>`
  }


  async function loadProfileDetails(id){
    if(!sb){S.profileDetails={...S.profile,id,rank:1,mostPlayed:'Geral',games:S.profile?.wins||0,accuracy:0};return render()}
    let {data:p,error}=await sb.from('profiles').select('id,username,display_name,avatar_url,xp,level,wins,losses,streak,coins,draws,premium_vip,premium_frame,premium_effect,premium_theme,premium_avatar,premium_title,premium_badge').eq('id',id).single();
    if(error){const fallback=await sb.from('profiles').select('id,username,display_name,avatar_url,xp,level,wins,losses,streak').eq('id',id).single();p=fallback.data;error=fallback.error;}
    if(error||!p){alert(error?.message||'Perfil não encontrado.');return go('home')}
    const [{data:all},{data:results}]=await Promise.all([sb.from('profiles').select('id,xp').order('xp',{ascending:false}),sb.from('game_results').select('category,score,won,outcome').eq('user_id',id)]);
    const rows=all||[],rr=results||[];const rank=(rows.findIndex(r=>r.id===id)+1)||'-';const games=rr.length;const most=rr.reduce((acc,r)=>(acc[r.category]=(acc[r.category]||0)+1,acc),{});const mostPlayed=Object.entries(most).sort((a,b)=>b[1]-a[1])[0]?.[0]||'Ainda não jogou';
    S.profileDetails={...p,rank,games,mostPlayed,draws:Number(p.draws??rr.filter(r=>r.outcome==='draw').length),accuracy:games?Math.round((rr.filter(r=>r.outcome==='win'||(r.outcome==null&&r.won)).length/games)*100):0};render()
  }
  function friends(){
    if(!S.friendRows){setTimeout(loadFriends,0);return `<div class="title">Amigos</div><div class="card pad center"><div class="muted">Carregando amizades...</div></div>`}
    const {list,people,head}=S.friendRows;const challenges=S.challengeRows||[];const term=S.challengeSearch.trim().toLowerCase();const cats=(S.categories||[]).filter(c=>!term||c.name.toLowerCase().includes(term));const mainCats=cats.filter(c=>!c.parent_id).slice(0,6);const otherCats=cats.filter(c=>c.parent_id||!mainCats.some(x=>x.id===c.id));
    const received=challenges.filter(c=>!c.mine&&c.status==='pending'),sent=challenges.filter(c=>c.mine&&c.status==='pending'),accepted=challenges.filter(c=>c.status==='accepted'),declined=challenges.filter(c=>c.mine&&c.status==='declined');
    return `<section class="friends-page"><div class="title">Amigos</div><form id="friendSearch" class="searchbar"><input id="friendName" required placeholder="Nome de usuário exato"><button>ADICIONAR</button></form><div class="friends-list-card card pad"><div class="friends-headline"><div><b>👥 Seus amigos</b><small>Histórico somente de partidas finalizadas</small></div><span>${list.filter(f=>f.status==='accepted').length}</span></div>${list.filter(f=>f.status==='accepted').map(f=>{const other=people[f.requester_id===S.user.id?f.addressee_id:f.requester_id],h=head[other?.id]||{games:0,wins:0,losses:0,draws:0};return `<article class="friend-modern"><button class="plain-profile friend-avatar" data-profile="${other?.id||''}">${profileAvatarMarkup(other,'avatar mini')}</button><div class="friend-main"><b class="${other?.premium_vip||other?.premium_title?'premium-name-glow':''}">${esc(other?.username||'Jogador')}</b><div class="premium-game-identity">${profileIdentityMarkup(other)}</div><div class="friend-h2h"><span><b>${h.wins}</b>VIT</span><span><b>${h.losses}</b>DER</span><span><b>${h.draws}</b>EMP</span></div></div><div class="friend-actions"><button class="secondary chatFriend" data-id="${other?.id||''}" data-name="${esc(other?.username||'Jogador')}">💬</button><button class="secondary challengeFriend" data-id="${other?.id||''}" data-name="${esc(other?.username||'Jogador')}">⚔️</button></div></article>`}).join('')||'<div class="classic-empty">Você ainda não tem amigos.</div>'}${list.filter(f=>f.status==='pending'&&f.addressee_id===S.user.id).map(f=>{const other=people[f.requester_id];return `<article class="friend-modern request"><button class="plain-profile friend-avatar" data-profile="${other?.id||''}">${profileAvatarMarkup(other,'avatar mini')}</button><div class="friend-main"><b>${esc(other?.username||'Jogador')}</b><small>Quer ser seu amigo.</small></div><button class="primary acceptFriend" data-id="${f.id}">ACEITAR</button></article>`}).join('')}</div>
    ${received.length?`<div class="card pad challenge-card"><div class="friends-headline"><div><b>⚔️ Desafios recebidos</b><small>Você pode aceitar ou recusar</small></div></div>${received.map(c=>`<article class="challenge-row"><div>${profileAvatarMarkup({username:c.other_username,avatar_url:c.other_avatar_url},'avatar mini')}</div><div class="friend-main"><b>${esc(c.other_username)}</b><small>te desafiou em <strong>${esc(c.category)}</strong></small></div><button class="primary acceptChallenge" data-id="${c.id}">JOGAR</button><button class="danger declineChallenge" data-id="${c.id}">RECUSAR</button></article>`).join('')}</div>`:''}
    ${sent.length?`<div class="card pad challenge-card"><b>📤 Desafios enviados</b>${sent.map(c=>`<article class="challenge-row"><div>${profileAvatarMarkup({username:c.other_username,avatar_url:c.other_avatar_url},'avatar mini')}</div><div class="friend-main"><b>${esc(c.other_username)}</b><small>${esc(c.category)} • aguardando resposta</small></div></article>`).join('')}</div>`:''}
    ${accepted.length?`<div class="card pad challenge-card"><b>🎮 Desafios em andamento</b>${accepted.map(c=>`<article class="challenge-row"><div>${profileAvatarMarkup({username:c.other_username,avatar_url:c.other_avatar_url},'avatar mini')}</div><div class="friend-main"><b>${esc(c.other_username)}</b><small>${esc(c.category)} • desafio aceito</small></div>${c.match_id?`<button class="secondary continueChallenge" data-id="${c.id}">CONTINUAR</button>`:''}</article>`).join('')}</div>`:''}
    ${declined.length?`<div class="card pad challenge-card declined-challenge"><b>❌ Desafios recusados</b>${declined.map(c=>`<article class="challenge-row"><div class="friend-main"><b>${esc(c.other_username)}</b><small>recusou seu desafio em ${esc(c.category)}</small></div><button class="secondary dismissDeclined" data-id="${c.id}">ENTENDI</button></article>`).join('')}</div>`:''}
    ${S.challengeModal?`<div class="modal-backdrop"><div class="modal-card challenge-picker"><button class="modal-close" id="closeChallenge">×</button><div class="match-badge">⚔️ DESAFIAR</div><h2>Escolha a categoria</h2><div class="searchbar"><input id="challengeSearch" value="${esc(S.challengeSearch)}" placeholder="🔎 Pesquisar categoria..."></div><div class="challenge-cats">${(term?cats:mainCats).map(c=>`<button class="challenge-cat" data-challenge-cat="${esc(c.name)}"><span>${esc(c.icon||'🌐')}</span><b>${esc(c.name)}</b><small>${c.parent_id?'Subcategoria':'Principal'}</small></button>`).join('')||'<div class="notice">Nenhuma categoria encontrada.</div>'}</div>${!term&&otherCats.length?`<details class="more-cats"><summary>Ver outras categorias</summary><div class="challenge-cats">${otherCats.map(c=>`<button class="challenge-cat" data-challenge-cat="${esc(c.name)}"><span>${esc(c.icon||'🌐')}</span><b>${esc(c.name)}</b></button>`).join('')}</div></details>`:''}</div></div>`:''}<button class="secondary" id="friendsHome">← VOLTAR AO INÍCIO</button></section>`
  }
  async function loadFriends(){
    if(!sb)return;
    const {data,error}=await sb.from('friendships').select('id,requester_id,addressee_id,status,created_at').or(`requester_id.eq.${S.user.id},addressee_id.eq.${S.user.id}`).order('created_at',{ascending:false});
    if(error)return alert(error.message);
    const list=data||[];const ids=[...new Set(list.flatMap(f=>[f.requester_id,f.addressee_id]).filter(id=>id!==S.user.id))];let people={};
    if(ids.length){const {data:pdata}=await sb.from('profiles').select('id,username,display_name,avatar_url,xp,level,wins,losses,draws,premium_vip,premium_frame,premium_effect,premium_theme,premium_avatar,premium_title,premium_badge').in('id',ids);(pdata||[]).forEach(p=>people[p.id]=p)}
    let head={};
    if(ids.length){const {data:matches}=await sb.from('matches').select('id,player_ids,scores,status,created_at').eq('status','finished').contains('player_ids',[S.user.id]).order('created_at',{ascending:false}).limit(500);(matches||[]).forEach(m=>{const rival=(m.player_ids||[]).find(x=>x!==S.user.id);if(!rival||!ids.includes(rival))return;const mine=Number(m.scores?.[S.user.id]||0),opp=Number(m.scores?.[rival]||0);const h=head[rival]||{games:0,wins:0,losses:0,draws:0};h.games++;if(mine>opp)h.wins++;else if(mine<opp)h.losses++;else h.draws++;head[rival]=h;});}
    const {data:ch,error:chErr}=await sb.from('challenges').select('id,challenger_id,challenged_id,category,status,match_id,created_at,decline_seen_by_challenger').or(`challenged_id.eq.${S.user.id},challenger_id.eq.${S.user.id}`).in('status',['pending','accepted','declined']).order('created_at',{ascending:false});
    if(chErr)console.warn(chErr.message);
    let challengeRows=ch||[];
    if(challengeRows.length){const ids2=[...new Set(challengeRows.map(x=>x.challenger_id===S.user.id?x.challenged_id:x.challenger_id))];const {data:cp}=await sb.from('profiles').select('id,username,display_name,avatar_url,xp,level,wins,losses,draws,premium_vip,premium_frame,premium_effect,premium_theme,premium_avatar,premium_title,premium_badge').in('id',ids2);const pm={};(cp||[]).forEach(x=>pm[x.id]=x);challengeRows=challengeRows.map(x=>({...x,other_id:x.challenger_id===S.user.id?x.challenged_id:x.challenger_id,other_username:pm[x.challenger_id===S.user.id?x.challenged_id:x.challenger_id]?.username||'Jogador',other_avatar_url:pm[x.challenger_id===S.user.id?x.challenged_id:x.challenger_id]?.avatar_url||'',mine:x.challenger_id===S.user.id})).filter(x=>x.status!=='declined'||(x.mine&&!x.decline_seen_by_challenger));}
    S.friendRows={list,people,head};S.challengeRows=challengeRows;render()
  }
  async function acceptChallenge(id){await openAsyncChallenge(id)}
  async function declineChallenge(id){if(!sb||!id)return;const {data,error}=await sb.rpc('decline_friend_challenge',{p_challenge_id:id});if(error){const r=await sb.from('challenges').update({status:'declined',decline_seen_by_challenger:false}).eq('id',id).eq('challenged_id',S.user.id);if(r.error)return alert(error.message)}S.challengeRows=null;S.friendRows=null;await loadFriends()}
  async function dismissDeclined(id){if(!sb||!id)return;const {error}=await sb.rpc('mark_declined_challenge_seen',{p_challenge_id:id});if(error){await sb.from('challenges').update({decline_seen_by_challenger:true}).eq('id',id).eq('challenger_id',S.user.id)}S.friendRows=null;await loadFriends()}
  async function editPremiumItem(id){const x=(S.adminPremiumItems||[]).find(i=>i.id===id);if(!x)return;const price=prompt('Preço normal em QuizCoins:',String(x.price_coins??x.price_cents??0));if(price===null)return;const promo=prompt('Preço promocional em QuizCoins (vazio para remover):',String(x.promo_price_coins??x.promo_price_cents??''));if(promo===null)return;const exp=prompt('Fim da promoção ISO (opcional, ex.: 2026-12-31T23:59:00-03:00):',x.promo_expires_at||'');if(exp===null)return;const pp=Number(promo||0);const payload={price_cents:Number(price||0),price_coins:Number(price||0),promo_price_cents:pp>0?pp:null,promo_price_coins:pp>0?pp:null,promo_active:pp>0&&pp<Number(price||0),promo_expires_at:exp?exp:null};const {error}=await sb.from('premium_items').update(payload).eq('id',id);if(error)alert(error.message);else{alert('Preço/promoção atualizados.');await loadAdminPremiumItems();await loadPremiumItems();render()}}
  async function togglePremiumItem(id,active){const {error}=await sb.from('premium_items').update({active:!active}).eq('id',id);if(error)alert(error.message);else{await loadAdminPremiumItems();await loadPremiumItems();render()}}
  async function bindAdmin(){if(!sb)return;$('#adminHome')?.addEventListener('click',()=>go('home'));$('#catForm')?.addEventListener('submit',async e=>{e.preventDefault();const {error}=await sb.from('categories').insert({name:$('#catName').value.trim(),icon:$('#catIcon').value.trim()||'🌐',description:$('#catDesc').value.trim()||null,parent_id:$('#catParent').value||null,approved:true,created_by:S.user.id});if(error)alert(error.message);else{alert('Categoria criada.');await loadAdminQuestions()}});$('#qForm')?.addEventListener('submit',async e=>{e.preventDefault();const options=[$('#q0').value.trim(),$('#q1').value.trim(),$('#q2').value.trim(),$('#q3').value.trim()];const {error}=await sb.from('questions').insert({category_name:$('#qCat').value,question_text:$('#qText').value.trim(),options,correct_index:+$('#qCorrect').value,image_url:$('#qImage').value.trim()||null,created_by:S.user.id,approval_status:'approved',active:true});if(error)alert(error.message);else{alert('Pergunta salva.');await loadAdminQuestions()}});$('#premiumItemFile')?.addEventListener('change',e=>{const f=e.target.files?.[0];const el=$('#premiumItemFileName');if(el)el.textContent=f?`${f.name} • ${(f.size/1024/1024).toFixed(1)} MB`:'Nenhum arquivo selecionado';});
    $('#premiumItemForm')?.addEventListener('submit',async e=>{e.preventDefault();await createPremiumItem()});$$('.editPremium').forEach(b=>b.onclick=()=>editPremiumItem(b.dataset.id));$$('.togglePremium').forEach(b=>b.onclick=()=>togglePremiumItem(b.dataset.id,b.dataset.active==='true'));$('#saveStoreSettings')?.addEventListener('click',async()=>{const payload={enabled:!!$('#storeEnabled')?.checked,cosmetics_enabled:!!$('#storeCosmetics')?.checked,vip_enabled:!!$('#storeVip')?.checked,coins_enabled:!!$('#storeCoins')?.checked,pass_enabled:!!$('#storePass')?.checked};const {error}=await sb.from('premium_store_settings').upsert({id:1,...payload});if(error)alert(error.message);else{S.storeSettings=payload;alert('Controles da loja atualizados.');render()}});
    $('#achievementForm')?.addEventListener('submit',e=>{e.preventDefault();createAchievement()});$('#reloadQuestions')?.addEventListener('click',loadAdminQuestions);$('#adminSearch')?.addEventListener('input',e=>{S.adminSearch=e.target.value;render()});$('#adminCategory')?.addEventListener('change',e=>{S.adminCategory=e.target.value;render()});$$('.editQuestion').forEach(b=>b.onclick=()=>editQuestion(b.dataset.id));$$('.toggleQuestion').forEach(b=>b.onclick=()=>toggleQuestion(b.dataset.id,b.dataset.active==='true'));$$('.deleteQuestion').forEach(b=>b.onclick=()=>deleteQuestion(b.dataset.id));$$('.approveCategory').forEach(b=>b.onclick=()=>approveCategory(b.dataset.id,true));$$('.rejectCategory').forEach(b=>b.onclick=()=>approveCategory(b.dataset.id,false));$$('.approveQuestion').forEach(b=>b.onclick=()=>approveQuestion(b.dataset.id,true));$$('.rejectQuestion').forEach(b=>b.onclick=()=>approveQuestion(b.dataset.id,false));$$('.approvePackage').forEach(b=>b.onclick=()=>approveCategoryPackage(b.dataset.id,true));$$('.rejectPackage').forEach(b=>b.onclick=()=>approveCategoryPackage(b.dataset.id,false));$$('.toggleAchievement').forEach(b=>b.onclick=()=>toggleAchievement(b.dataset.id,b.dataset.active==='true'));$$('.deleteAchievement').forEach(b=>b.onclick=()=>deleteAchievement(b.dataset.id))}
  async function sendMatchReaction(emoji){if(!sb||!S.matchId||!S.user||!emoji)return;S.emojiOpen=false;const reaction={id:`local-${Date.now()}-${Math.random().toString(36).slice(2,7)}`,match_id:S.matchId,sender_id:S.user.id,emoji,created_at:new Date().toISOString()};if(!S.matchReactions.some(x=>x.sender_id===S.user.id&&x.emoji===emoji&&Date.now()-new Date(x.created_at).getTime()<400)){S.matchReactions.push(reaction);if(S.matchReactions.length>10)S.matchReactions.shift();S.lastReaction=emoji;render();}const {error}=await sb.from('match_reactions').insert({match_id:S.matchId,sender_id:S.user.id,emoji});if(error)console.warn('reaction',error.message);if(S.realtime){try{await S.realtime.send({type:'broadcast',event:'reaction',payload:{...reaction}})}catch(e){}}setTimeout(()=>{S.lastReaction='';render()},1800)}
  function bind(){
    $('#soundToggle')?.addEventListener('click',()=>{S.soundOn=!S.soundOn;localStorage.setItem('quizup_sound',S.soundOn?'on':'off');if(S.soundOn)audio();render()});
    $$('.primary,.secondary,.quick button,.power button,.classic-bottom button,.cat,.challenge-cat,.chat-tool,.send-chat').forEach(b=>b.addEventListener('click',()=>{if(b.id!=='soundToggle')sound('click')},{once:true}));
    $$('.classic-bottom button').forEach(b=>b.onclick=()=>{if(b.dataset.r==='profile')goProfile();else if(b.dataset.r)go(b.dataset.r)});$('#classicHome')?.addEventListener('click',()=>go('home'));$('#topProfile')?.addEventListener('click',()=>goProfile());$('#quickPlay')?.addEventListener('click',()=>go('categories'));$('#storeBtn')?.addEventListener('click',()=>go('store'));$('#storeHome')?.addEventListener('click',()=>go('home'));$$('[data-coin-package]').forEach(b=>b.onclick=()=>alert('💳 Pacote selecionado. A confirmação de pagamento real será conectada ao gateway antes de liberar Coins.'));$('#coinPackageForm')?.addEventListener('submit',async e=>{e.preventDefault();await createCoinPackage()});$$('.editCoinPackage').forEach(b=>b.onclick=()=>editCoinPackage(b.dataset.id));$('#buyCoins')?.addEventListener('click',async()=>{S.premium.coins=Number(S.profile?.coins??S.premium.coins??0)+2500;S.profile={...S.profile,coins:S.premium.coins};if(sb&&S.user)await sb.from('profiles').update({coins:S.premium.coins}).eq('id',S.user.id);premiumSave();alert('2.500 QuizCoins adicionadas para testar a loja.');render()});$$('[data-premium-buy]').forEach(b=>b.onclick=()=>premiumBuy(b.dataset.premiumBuy));$$('[data-premium-cat]').forEach(b=>b.onclick=()=>{const cat=b.dataset.premiumCat;const grid=$('#premiumAllGrid');if(grid)grid.innerHTML=premiumCatalog().filter(x=>x.cat===cat).map(premiumCard).join('');grid&&grid.scrollIntoView({behavior:'smooth',block:'start'});setTimeout(()=>$$('[data-premium-buy]').forEach(x=>x.onclick=()=>premiumBuy(x.dataset.premiumBuy)),0)});$('#profileStore')?.addEventListener('click',()=>go('store'));$$('[data-use-premium]').forEach(b=>b.onclick=()=>useInventoryItem(b.dataset.usePremium));$('#topSearch')?.addEventListener('click',()=>go('categories'));$$('[data-go]')?.forEach(b=>b.addEventListener('click',()=>go(b.dataset.go)));$$('[data-topic]').forEach(b=>b.onclick=()=>{S.topicCategory=b.dataset.topic;S.topicStats=null;S.topicRows=null;go('topic')});
    $$('.quick button').forEach(b=>b.onclick=()=>go(b.dataset.go));
    $$('.player-row').forEach(b=>b.onclick=()=>goProfile(b.dataset.profile));
    $$('.plain-profile').forEach(b=>b.onclick=()=>b.dataset.profile&&goProfile(b.dataset.profile));
    $('#notificationsBtn')?.addEventListener('click',async()=>{await loadNotifications();go('notifications')});$('#notificationsHomeTop')?.addEventListener('click',()=>go('notifications'));$('#notificationsHome')?.addEventListener('click',()=>go('home'));$('#markAllNotifications')?.addEventListener('click',markAllNotifications);$$('.notification-item').forEach(el=>el.onclick=()=>{const n=S.notifications.find(x=>x.id===el.dataset.notificationId);openNotification(n)});    $('#signupGo')?.addEventListener('click',()=>go('signup'));$('#loginGo')?.addEventListener('click',()=>go('login'));
    $('#loginForm')?.addEventListener('submit',async e=>{e.preventDefault();
      if(!sb)return alert('Supabase não está configurado. Configure o config.js antes de entrar.');
      let identifier=$('#identifier').value.trim();let email=identifier;if(!identifier.includes('@')){const {data,error}=await sb.rpc('get_login_email',{p_username:identifier});if(error||!data)return alert('Nome de usuário não encontrado.');email=data}const {error}=await sb.auth.signInWithPassword({email,password:$('#password').value});if(error){S.enterMultiplayer=false;alert(error.message)}
    });
    $('#signupForm')?.addEventListener('submit',async e=>{e.preventDefault();if(!sb)return;const username=$('#username').value.trim();const email=$('#email').value.trim().toLowerCase();const password=$('#password').value;if(!/^[A-Za-z0-9_]{3,20}$/.test(username))return alert('Nome de usuário inválido. Use de 3 a 20 caracteres: letras, números e _.');if(!/^[A-Za-z0-9]{6,}$/.test(password))return alert('Senha inválida. Use no mínimo 6 caracteres, somente letras e números.');if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return alert('Digite um e-mail válido.');const {data:available,error:avErr}=await sb.rpc('is_username_available',{p_username:username.toLowerCase()});if(!avErr&&available===false)return alert('Esse nome de usuário já está em uso. Escolha outro.');const {data,error}=await sb.auth.signUp({email,password,options:{data:{username:username.toLowerCase(),display_name:username}}});if(error){if(/already|duplicate|registered|exists|uso|unique/i.test(error.message))alert('Esse e-mail ou nome de usuário já está cadastrado.');else alert(error.message);return}alert(data?.session?'Conta criada com sucesso!':'Conta criada. Verifique o e-mail se a confirmação estiver ativada no Supabase.');if(data?.session)go('home');else go('login')});
    $('#logoutProfile')?.addEventListener('click',async()=>{if(confirm('Deseja sair da sua conta?'))$('#logout')?.click()});$('#logoutTop')?.addEventListener('click',async()=>{if(confirm('Deseja sair da sua conta?'))$('#logout')?.click()});$('#logout')?.addEventListener('click',async()=>{if(S.challengeRealtime&&sb){sb.removeChannel(S.challengeRealtime);S.challengeRealtime=null}if(S.notificationRealtime&&sb){sb.removeChannel(S.notificationRealtime);S.notificationRealtime=null}if(sb)await sb.auth.signOut();S.user=null;S.profile=null;go('login')});
    $('#play')?.addEventListener('click',()=>{S.mode='1v1';go('categories')});
    $$('.cat,.topic-list-row').forEach(b=>b.onclick=()=>{S.topicCategory=b.dataset.cat;S.topicStats=null;S.topicRows=null;go('topic')});$('#topicPlay')?.addEventListener('click',()=>{S.category=S.topicCategory;S.mode='1v1';S.searching=false;S.searchStartedAt=Date.now();S.match=null;S.matchId=null;S.botOffer=false;go('match')});$('#topicRanking')?.addEventListener('click',()=>{S.rankCategory=S.topicCategory;S.rankRows=null;go('ranking')});$('#backTopics')?.addEventListener('click',()=>go('categories'));
    $('#cancel')?.addEventListener('click',async()=>{if(sb)await sb.rpc('cancel_match_queue');S.searching=false;S.botOffer=false;go('categories')});$('#playBot')?.addEventListener('click',startBotMatch);$('#continueReal')?.addEventListener('click',()=>{S.botOffer=false;S.searchStartedAt=Date.now();S.searching=true;findMatch()});
    // RESPOSTAS — bind direto + pointer/click para iOS/Safari.
    // Não dependemos de um listener global criado apenas uma vez: cada renderização
    // recebe novamente seus próprios handlers. Um pequeno lock evita que pointerup
    // e click disparem a mesma resposta duas vezes.
    $$('.neon-answer,.classic-answer,.answer').forEach(b=>{
      b.type='button';
      b.style.touchAction='manipulation';
      b.onclick=null;
      b.onpointerup=null;
      let handledAt=0;
      const fire=ev=>{
        if(ev){ev.preventDefault();ev.stopPropagation();}
        const now=Date.now();
        if(now-handledAt<450||b.disabled)return;
        handledAt=now;
        if(b.dataset.a!==undefined){answer(Number(b.dataset.a));return;}
        if(b.dataset.asyncA!==undefined){submitAsyncAnswer(Number(b.dataset.asyncA));return;}
      };
      b.onpointerup=fire;
      b.onclick=fire;
    });
    $$('[data-async-a]').forEach(b=>{b.type='button'});$('#asyncBackFriends')?.addEventListener('click',()=>{S.asyncMode=false;S.asyncChallengeId=null;go('friends')});
    $('#matchEmojiBtn')?.addEventListener('click',()=>{S.emojiOpen=!S.emojiOpen;render()});$$('[data-match-emoji]').forEach(b=>b.onclick=()=>sendMatchReaction(b.dataset.matchEmoji));$('#plus')?.addEventListener('click',()=>{if(!S.plusUsed&&!S.answered&&!S.waiting){S.plusUsed=true;/* bônus visual apenas; o relógio oficial continua em 10s no modo clássico */}});
    $('#fifty')?.addEventListener('click',()=>{if(S.fiftyUsed||S.answered)return;S.fiftyUsed=true;const q=S.questions[S.questionIndex];if(!q)return;const correct=q.correct_index;[0,1,2,3].filter(i=>i!==correct).sort(()=>Math.random()-.5).slice(0,2).forEach(i=>document.querySelector(`[data-a="${i}"]`)?.classList.add('dim'))});
    $('#rematch')?.addEventListener('click',requestRematch);$('#findAnother')?.addEventListener('click',()=>{S.rematchMessage='';S.category=S.category;S.searching=false;S.searchStartedAt=Date.now();go('match')});$('#again')?.addEventListener('click',()=>go('categories'));$('#home')?.addEventListener('click',()=>go('home'));$('#friendsBtn')?.addEventListener('click',()=>go('friends'));$('#backRank')?.addEventListener('click',()=>go('ranking'));$('#adminBtn')?.addEventListener('click',()=>go('admin'));$('#rankCategory')?.addEventListener('change',e=>{S.rankCategory=e.target.value;S.rankRows=null;loadRanking()});$('#resultChat')?.addEventListener('click',()=>{const id=(S.match?.player_ids||[]).find(x=>x!==S.user.id);if(id)openChat(id,S.matchPlayers[id]?.username||'Oponente')});$('#publishResult')?.addEventListener('click',async()=>{try{await navigator.clipboard.writeText(`QuizUp • ${S.category} • ${S.myScore||getScore(S.user.id)} pontos`);alert('Resultado copiado para compartilhar!')}catch(e){alert('Resultado pronto para compartilhar!')}});
    $('#friendSearch')?.addEventListener('submit',e=>{e.preventDefault();sendFriend($('#friendName').value)});$('#closeChallenge')?.addEventListener('click',()=>{S.challengeModal=false;render()});$('#challengeSearch')?.addEventListener('input',e=>{S.challengeSearch=e.target.value;render();setTimeout(()=>$('#challengeSearch')?.focus(),0)});$$('[data-challenge-cat]').forEach(b=>b.onclick=()=>chooseChallengeCategory(b.dataset.challengeCat));$$('.acceptFriend').forEach(b=>b.onclick=()=>acceptFriend(b.dataset.id));$$('.chatFriend').forEach(b=>b.onclick=()=>openChat(b.dataset.id,b.dataset.name));$$('.challengeFriend').forEach(b=>b.onclick=()=>challengeFriend(b.dataset.id,b.dataset.name));$$('.acceptChallenge').forEach(b=>b.onclick=()=>acceptChallenge(b.dataset.id));$$('.declineChallenge').forEach(b=>b.onclick=()=>declineChallenge(b.dataset.id));$$('.dismissDeclined').forEach(b=>b.onclick=()=>dismissDeclined(b.dataset.id));$$('.continueChallenge').forEach(b=>b.onclick=()=>openAsyncChallenge(b.dataset.id));$('#friendsHome')?.addEventListener('click',()=>go('home'));$('#backFriends')?.addEventListener('click',()=>{if(S.realtime){sb.removeChannel(S.realtime);S.realtime=null}S.friendRows=null;go('friends')});$('#chatForm')?.addEventListener('submit',e=>{e.preventDefault();sendChat()});$('#emojiBtn')?.addEventListener('click',()=>{S.emojiOpen=!S.emojiOpen;render()});$$('.emoji-btn').forEach(b=>b.onclick=()=>{const input=$('#chatInput');if(input){input.value+=(b.dataset.emoji||'');input.focus()}S.emojiOpen=false;render();setTimeout(()=>$('#chatInput')?.focus(),0)});$('#chatPhoto')?.addEventListener('change',e=>sendChatPhoto(e.target.files?.[0]));
    $('#avatarFile')?.addEventListener('change',e=>uploadAvatar(e.target.files?.[0]));
    $('#categorySearch')?.addEventListener('input',e=>{S.categorySearch=e.target.value;render()});$('#clearCategorySearch')?.addEventListener('click',()=>{S.categorySearch='';render()});$('#contributeGo')?.addEventListener('click',()=>go('contribute'));$('#backCategories')?.addEventListener('click',()=>go('categories'));
    $$('.cq-type').forEach(sel=>sel.addEventListener('change',()=>{const i=sel.id.replace('cqType','');const w=$(`#cqImageWrap${i}`);if(w)w.hidden=sel.value!=='image';}));
    $$('[id^="cqImage"]').forEach(input=>{if(input.type!=='file')return;input.addEventListener('change',()=>{const i=input.id.replace('cqImage','');const file=input.files?.[0];const name=$(`#cqImageName${i}`);const preview=$(`#cqImagePreview${i}`);if(!file){if(name)name.textContent='Nenhuma imagem selecionada';if(preview){preview.hidden=true;preview.removeAttribute('src')}return}if(file.size>5*1024*1024){alert('A imagem deve ter no máximo 5 MB.');input.value='';return}if(!file.type.startsWith('image/')){alert('Escolha uma imagem válida.');input.value='';return}if(name)name.textContent=`${file.name} • ${(file.size/1024/1024).toFixed(1)} MB`;if(preview){preview.src=URL.createObjectURL(file);preview.hidden=false}})});
    async function uploadQuestionImage(file,index){if(!sb||!S.user||!file)return null;if(file.size>5*1024*1024)throw new Error(`A imagem da pergunta ${index+1} deve ter no máximo 5 MB.`);if(!file.type.startsWith('image/'))throw new Error(`A imagem da pergunta ${index+1} não é válida.`);const ext=(file.type.split('/')[1]||'jpg').toLowerCase().replace(/[^a-z0-9]/g,'')||'jpg';const path=`${S.user.id}/${Date.now()}-${index}-${Math.random().toString(36).slice(2,8)}.${ext}`;const {error}=await sb.storage.from('question-images').upload(path,file,{cacheControl:'31536000',upsert:false,contentType:file.type});if(error)throw new Error(`Falha ao enviar a imagem da pergunta ${index+1}: ${error.message}`);const {data}=sb.storage.from('question-images').getPublicUrl(path);return data.publicUrl}
    $('#categoryPackageForm')?.addEventListener('submit',async e=>{e.preventDefault();if(!sb||!S.user)return;const name=$('#packageCatName').value.trim();const icon=$('#packageCatIcon').value.trim()||'🌐';const description=$('#packageCatDesc').value.trim()||null;if(name.length<2)return alert('Digite um nome válido para a categoria.');const questions=[];for(let i=0;i<10;i++){const text=$(`#cqText${i}`).value.trim();const options=[0,1,2,3].map(j=>$(`#cq${j}_${i}`).value.trim());const correct=Number($(`#cqCorrect${i}`).value);if(!text||options.some(x=>!x))return alert(`Preencha a pergunta ${i+1} e as 4 respostas.`);if(new Set(options.map(x=>x.toLowerCase())).size<4)return alert(`A pergunta ${i+1} precisa ter 4 respostas diferentes.`);if(!Number.isInteger(correct)||correct<0||correct>3)return alert(`Escolha a resposta correta da pergunta ${i+1}.`);const type=$(`#cqType${i}`)?.value||'text';const file=$(`#cqImage${i}`)?.files?.[0]||null;if(type==='image'&&!file)return alert(`Escolha uma imagem para a pergunta ${i+1}.`);questions.push({question_text:text,options,correct_index:correct,image_url:null,_imageFile:file});}const btn=$('#submitCategoryPackage');if(btn)btn.disabled=true;try{for(let i=0;i<questions.length;i++){if(questions[i]._imageFile)questions[i].image_url=await uploadQuestionImage(questions[i]._imageFile,i);delete questions[i]._imageFile;}const {data,error}=await sb.rpc('submit_category_package',{p_name:name,p_icon:icon,p_description:description,p_questions:questions});if(error)throw error;alert('✅ Categoria enviada! As imagens foram salvas no Supabase Storage e o pacote foi enviado para revisão do administrador.');go('categories')}catch(err){alert(err?.message||'Não foi possível enviar a categoria.')}finally{if(btn)btn.disabled=false}});
    if(S.route==='admin'){bindAdmin();if(!S.adminQuestions.length)setTimeout(loadAdminQuestions,0);if(!S.adminAccounts.length)setTimeout(loadAdminAccounts,0);if(!S.adminCoinPackages.length)setTimeout(loadAdminCoinPackages,0);$$('.adminTitle').forEach(b=>b.onclick=()=>awardAdminTitle(b.dataset.id));$$('.adminReset').forEach(b=>b.onclick=()=>sendAdminReset(b.dataset.email));$$('.adminEmail').forEach(b=>b.onclick=()=>sendAdminEmailChange(b.dataset.id,b.dataset.email))}
  }

  document.addEventListener('visibilitychange',async()=>{
    if(document.hidden){S.backgrounded=true;return;}
    S.backgrounded=false;
    if(!S.user||!sb||!S.matchId||S.botMode||!['match','game'].includes(S.route))return;
    // Ao voltar para o app, sempre busca o estado autoritativo do servidor.
    const {data,error}=await sb.from('matches').select('*').eq('id',S.matchId).single();
    if(!error&&data){await loadMatchPlayers(data);await syncMatch(data);if(data.status!=='finished'&&S.route==='game'&&!S.answered&&!S.waiting)startClock();}
  });
  window.addEventListener('focus',async()=>{if(document.hidden||!S.user||!sb||!S.matchId||S.botMode||!['match','game'].includes(S.route))return;const {data}=await sb.from('matches').select('*').eq('id',S.matchId).single();if(data)await syncMatch(data);});

  premiumLoad();async function init(){if(!sb){S.user=null;S.profile=null;S.profileTargetId=null;return go('login')}const {data:{session}}=await sb.auth.getSession();S.accessToken=session?.access_token||null;const {data:{user}}=await sb.auth.getUser();S.user=user||null;if(!S.user)return go('login');subscribeChallenges();subscribeNotifications();await loadProfile();await loadCategories();await loadPremiumItems();await loadCoinPackages();await loadStoreSettings();await loadNotifications();S.achievementsRows=null;S.profileTargetId=S.user.id;let restored='home';try{restored=sessionStorage.getItem('quizup_route')||'home';const mid=sessionStorage.getItem('quizup_match_id');if(mid)S.matchId=mid;const aid=sessionStorage.getItem('quizup_async_id');if(aid)S.asyncChallengeId=aid;}catch(e){}if(['login','signup','admin'].includes(restored)&&!S.isAdmin)restored='home';if(restored==='async-game'&&S.asyncChallengeId){await openAsyncChallenge(S.asyncChallengeId);return}if(['game','match','result'].includes(restored)&&S.matchId){const {data:m}=await sb.from('matches').select('*').eq('id',S.matchId).maybeSingle();if(m){S.match=m;S.mode=m.mode;S.category=m.category;S.questionIndex=Number(m.current_question||0);if(m.status==='finished'){await loadMatchPlayers(m);await loadMatchQuestions();await finishOnline();return;}if(['game','match'].includes(restored)){await loadMatchPlayers(m);await loadMatchQuestions();subscribeMatch();S.route=restored;startMatchPresence();if(restored==='game'&&Number(m.state?.question_started_at||0)>0)startClock();else startMatchCountdown();return;}}restored='home'}if(restored==='friends')S.friendRows=null;if(restored==='profile')S.profileDetails=null;go(restored)}
  if(sb){sb.auth.getSession().then(init);sb.auth.onAuthStateChange((_event,session)=>{S.accessToken=session?.access_token||null;setTimeout(init,0)})}else init();
})();
