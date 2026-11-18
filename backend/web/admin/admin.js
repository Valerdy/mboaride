/* MboaRide · Console d'administration de la plateforme.
 *
 * Application d'une page, sans dépendance : routage par l'ancre (#/utilisateurs/12),
 * connexion par l'API Node (même compte que l'application), données par /api/admin.
 */
'use strict';
(() => {
  // --- Outils --------------------------------------------------------------------------------
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const nf = new Intl.NumberFormat('fr-FR');
  const nb = (n) => nf.format(Math.round(Number(n) || 0));
  const fcfa = (n) => `${nb(n)} FCFA`;
  const enDate = (s) => (s ? new Date(String(s).length === 10 ? `${s}T00:00:00` : s) : null);
  const jour = (s) => (s ? enDate(s).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' }) : '—');
  const jourCourt = (s) => enDate(s).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' });
  const quand = (s) => (s ? enDate(s).toLocaleString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—');
  const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  const initiales = (nom) => String(nom || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((m) => m[0].toUpperCase()).join('');
  const compact = (v) => (v >= 1e6 ? `${(v / 1e6).toLocaleString('fr-FR', { maximumFractionDigits: 1 })} M`
    : v >= 1e3 ? `${(v / 1e3).toLocaleString('fr-FR', { maximumFractionDigits: 1 })} k` : nb(v));
  const qs = (o) => new URLSearchParams(Object.entries(o).filter(([, v]) => v !== '' && v !== null && v !== undefined)).toString();
  const JOURS = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
  const joursLabel = (s) => {
    if (!s) return '';
    const on = [...s].map((c, i) => (c === '1' ? i : -1)).filter((i) => i >= 0);
    if (on.length === 7) return 'Tous les jours';
    if (s === '1111100') return 'Lun. à ven.';
    return on.map((i) => JOURS[i]).join(', ');
  };
  const horaire = (t) => `${t.date_unique ? `Le ${jour(t.date_unique)}` : joursLabel(t.jours_semaine)} · ${t.heure_depart || t.heure || ''}`;

  const ICONES = {
    home: '<path d="M3 11.5 12 4l9 7.5"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/>',
    users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.6 3.4-5.5 6.5-5.5s5.7 1.9 6.5 5.5"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18 14.8c1.9.7 3.1 2.4 3.5 5.2"/>',
    shield: '<path d="M12 3 4.5 6v5.5c0 4.6 3.1 8.3 7.5 9.5 4.4-1.2 7.5-4.9 7.5-9.5V6L12 3z"/><path d="m8.8 12.2 2.2 2.2 4.4-4.6"/>',
    route: '<circle cx="6" cy="18" r="2.5"/><circle cx="18" cy="6" r="2.5"/><path d="M8.5 18H15a3.5 3.5 0 0 0 0-7H9a3.5 3.5 0 0 1 0-7h6.5"/>',
    card: '<rect x="2.5" y="5" width="19" height="14" rx="3"/><path d="M2.5 10h19M6.5 15h4"/>',
    chart: '<path d="M4 20V10M10 20V4M16 20v-7M21 20H3"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9M17 6l3 3M14.5 8.5l2 2"/>',
    list: '<path d="M8 6h13M8 12h13M8 18h13"/><circle cx="3.5" cy="6" r="1"/><circle cx="3.5" cy="12" r="1"/><circle cx="3.5" cy="18" r="1"/>',
    out: '<path d="M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3M10 16l4-4-4-4M14 12H4"/>',
    menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c1-4 4-6 8-6s7 2 8 6"/>',
    car: '<path d="M5 16V11l2-5h10l2 5v5"/><path d="M3 16h18v3H3z"/><circle cx="7.5" cy="16" r="1.5"/><circle cx="16.5" cy="16" r="1.5"/>',
    money: '<rect x="2.5" y="6" width="19" height="12" rx="2.5"/><circle cx="12" cy="12" r="2.8"/>',
    alert: '<path d="M12 3 2 20h20L12 3z"/><path d="M12 10v4M12 17h.01"/>',
    star: '<path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9L12 3z"/>',
    wallet: '<path d="M4 7h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h11"/><path d="M16 13.5h.01"/>',
    lock: '<rect x="4" y="10" width="16" height="11" rx="2.5"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
    download: '<path d="M12 4v11M7 10l5 5 5-5M4 20h16"/>',
    back: '<path d="M15 5l-7 7 7 7"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
    moon: '<path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z"/>',
  };
  const ico = (n) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONES[n] || ''}</svg>`;

  const PASTILLES = {
    agrement: { actif: ['good', 'Agréé'], en_verification: ['warn', 'En vérification'], suspendu: ['bad', 'Agrément suspendu'], non_demande: ['', 'Passager'] },
    piece: { valide: ['good', 'Validée'], depose: ['warn', 'À vérifier'], refuse: ['bad', 'Refusée'], expire: ['bad', 'Expirée'], manquant: ['', 'Manquante'] },
    trajet: { actif: ['good', 'En ligne'], retire: ['', 'Retiré'], passe: ['', 'Passé'] },
    reservation: { confirmee: ['info', 'Confirmée'], terminee: ['good', 'Terminée'], annulee: ['', 'Annulée'] },
    paiement: { reussi: ['good', 'Réussi'], en_attente: ['warn', 'En attente'], echoue: ['bad', 'Échoué'], rembourse: ['', 'Remboursé'] },
    course: { en_cours: ['info', 'En cours'], arrivee: ['warn', 'Arrivée'], reglee: ['good', 'Réglée'] },
    role: { super_admin: ['info', 'Super admin'], support: ['info', 'Support'], finance: ['info', 'Finance'] },
  };
  const pastille = (famille, v) => {
    const [ton, txt] = PASTILLES[famille]?.[v] || ['', v || '—'];
    return `<span class="pill ${ton}">${esc(txt)}</span>`;
  };
  const MOYENS = { mobile_money: 'Mobile Money', especes: 'Espèces', portefeuille: 'Portefeuille' };

  // --- Session ---------------------------------------------------------------------------------
  const CLE = 'mboaride_admin_session';
  const AUTH = (() => {
    const p = new URLSearchParams(location.search).get('auth');
    return (p || `${location.protocol}//${location.hostname}:8101`).replace(/\/$/, '');
  })();
  let session = null;
  try { session = JSON.parse(sessionStorage.getItem(CLE)); } catch { session = null; }
  const garder = (s) => {
    session = s;
    try { if (s) sessionStorage.setItem(CLE, JSON.stringify(s)); else sessionStorage.removeItem(CLE); } catch { /* navigation privée */ }
  };
  let moi = null;

  // Thème clair ou sombre : celui du système, sauf choix enregistré.
  const CLE_THEME = 'mboaride_admin_theme';
  const themeSysteme = () => (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  try { const t = localStorage.getItem(CLE_THEME); if (t) document.documentElement.dataset.theme = t; } catch { /* rien */ }
  const themeActuel = () => document.documentElement.dataset.theme || themeSysteme();
  const boutonTheme = () => (themeActuel() === 'dark'
    ? `${ico('sun').replace('<svg', '<svg width="15" height="15"')}Clair` : `${ico('moon').replace('<svg', '<svg width="15" height="15"')}Sombre`);
  function basculerTheme() {
    const t = themeActuel() === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = t;
    try { localStorage.setItem(CLE_THEME, t); } catch { /* rien */ }
    redessins.forEach((f) => f());
  }

  const messageErreur = (data) => {
    const d = data?.detail;
    if (!d) return data?.message || data?.error;
    if (typeof d === 'string') return d;
    if (Array.isArray(d)) return d.map((e) => String(e.msg || '').replace(/^Value error, /, '')).join(' · ');
    return d.message || JSON.stringify(d);
  };

  async function rafraichir() {
    if (!session?.refresh) return false;
    try {
      const r = await fetch(`${AUTH}/auth/refresh`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh_token: session.refresh }) });
      if (!r.ok) return false;
      const t = await r.json();
      garder({ ...session, jeton: t.access_token, refresh: t.refresh_token });
      return true;
    } catch { return false; }
  }

  async function api(chemin, { methode = 'GET', corps, brut = false, reessai = true } = {}) {
    const h = {};
    if (corps !== undefined) h['Content-Type'] = 'application/json';
    if (session?.jeton) h.Authorization = `Bearer ${session.jeton}`;
    else if (session?.uid) h['X-Utilisateur'] = String(session.uid);
    let r;
    try {
      r = await fetch(chemin, { method: methode, headers: h, body: corps === undefined ? undefined : JSON.stringify(corps) });
    } catch {
      throw new Error("Le serveur MboaRide ne répond pas : vérifiez que l'API Python tourne (port 8000).");
    }
    if (r.status === 401 && session) {
      if (reessai && await rafraichir()) return api(chemin, { methode, corps, brut, reessai: false });
      deconnexion('Votre session a expiré : reconnectez-vous.');
      throw new Error('Session expirée');
    }
    if (brut && r.ok) return r;
    const data = await r.json().catch(() => null);
    if (!r.ok) throw new Error(messageErreur(data) || `Erreur ${r.status}`);
    return data;
  }

  function deconnexion(msg) {
    if (session?.refresh) {
      fetch(`${AUTH}/auth/logout`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh_token: session.refresh }) }).catch(() => {});
    }
    garder(null);
    moi = null;
    history.replaceState(null, '', location.pathname + location.search);
    pageConnexion(msg);
  }

  // --- Retours visuels ---------------------------------------------------------------------------
  function toast(msg, mauvais = false) {
    const t = document.createElement('div');
    t.className = `toast${mauvais ? ' bad' : ''}`;
    t.textContent = msg;
    $('#toasts').append(t);
    setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 300); }, 4200);
  }

  /** Fenêtre de confirmation avec champs ; `action` reçoit les valeurs et peut échouer. */
  function demander({ titre, texte = '', champs = [], bouton = 'Confirmer', danger = false, action }) {
    const dlg = $('#dialogue');
    const champ = (c) => {
      const id = `ch-${c.nom}`;
      if (c.type === 'checkbox') {
        return `<label class="check"><input type="checkbox" id="${id}" name="${c.nom}" ${c.valeur ? 'checked' : ''}><span>${esc(c.label)}</span></label>`;
      }
      const attrs = `id="${id}" name="${c.nom}" ${c.requis ? 'required' : ''} ${c.min ? `min="${c.min}"` : ''} ${c.minlength ? `minlength="${c.minlength}"` : ''}`;
      const input = c.type === 'textarea' ? `<textarea ${attrs} placeholder="${esc(c.aide || '')}">${esc(c.valeur || '')}</textarea>`
        : c.type === 'select' ? `<select ${attrs}>${c.options.map(([v, l]) => `<option value="${esc(v)}" ${v === c.valeur ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`
          : `<input type="${c.type || 'text'}" ${attrs} value="${esc(c.valeur || '')}" placeholder="${esc(c.aide || '')}">`;
      return `<label class="field"><span>${esc(c.label)}</span>${input}</label>`;
    };
    dlg.innerHTML = `<form method="dialog" novalidate>
      <h2>${esc(titre)}</h2>${texte ? `<p>${texte}</p>` : ''}
      <div class="error" hidden></div>
      ${champs.map(champ).join('')}
      <div class="actions"><button type="button" class="btn ghost" value="annuler">Annuler</button>
      <button type="submit" class="btn ${danger ? 'danger' : ''}">${esc(bouton)}</button></div></form>`;
    return new Promise((resolve) => {
      const form = $('form', dlg);
      const err = $('.error', dlg);
      $('button[value="annuler"]', dlg).onclick = () => { dlg.close(); resolve(null); };
      dlg.oncancel = () => resolve(null);
      form.onsubmit = async (ev) => {
        ev.preventDefault();
        if (!form.reportValidity()) return;
        const vals = {};
        champs.forEach((c) => { const el = form.elements[c.nom]; vals[c.nom] = c.type === 'checkbox' ? el.checked : el.value.trim(); });
        const btn = $('button[type="submit"]', form);
        btn.disabled = true;
        try {
          const res = action ? await action(vals) : vals;
          dlg.close();
          resolve(res ?? vals);
        } catch (e) {
          err.textContent = e.message;
          err.hidden = false;
          btn.disabled = false;
        }
      };
      dlg.showModal();
      setTimeout(() => $('input:not([type="checkbox"]), textarea, select', form)?.focus(), 50);
    });
  }

  // --- Graphiques ----------------------------------------------------------------------------------
  let redessins = [];
  let attenteRedessin;
  window.addEventListener('resize', () => {
    clearTimeout(attenteRedessin);
    attenteRedessin = setTimeout(() => redessins.forEach((f) => f()), 150);
  });

  const graduer = (max) => {
    if (max <= 0) return 1;
    const p = 10 ** Math.floor(Math.log10(max));
    const r = max / p;
    return (r <= 1 ? 1 : r <= 2 ? 2 : r <= 5 ? 5 : 10) * p;
  };

  /** Histogramme d'une seule série, avec infobulle au survol. */
  function barres(conteneur, points, cle, format, hauteur = 190) {
    const dessiner = () => {
      const W = Math.max(conteneur.clientWidth, 260);
      const m = { t: 10, r: 6, b: 26, l: 46 };
      const iw = W - m.l - m.r;
      const ih = hauteur - m.t - m.b;
      const n = points.length || 1;
      const max = Math.max(0, ...points.map((p) => Number(p[cle]) || 0));
      const haut = graduer(max);
      const pas = iw / n;
      const ecart = n > 1 ? Math.max(2, pas * 0.22) : 0;
      const bw = Math.max(2, pas - ecart);
      const y = (v) => m.t + ih - (v / haut) * ih;
      const ticks = [0, haut / 2, haut];
      const indicesX = [...new Set([0, Math.floor((n - 1) / 2), n - 1])];
      let svg = `<svg viewBox="0 0 ${W} ${hauteur}" height="${hauteur}" role="img">`;
      ticks.forEach((t) => {
        svg += `<line class="gridline" x1="${m.l}" x2="${W - m.r}" y1="${y(t)}" y2="${y(t)}"/>`
          + `<text class="axis num" x="${m.l - 8}" y="${y(t) + 4}" text-anchor="end">${compact(t)}</text>`;
      });
      points.forEach((p, i) => {
        const v = Number(p[cle]) || 0;
        const x = m.l + i * pas + ecart / 2;
        const h = Math.max(0, (v / haut) * ih);
        const r = Math.min(4, bw / 2, h);
        const y0 = m.t + ih;
        if (h > 0) {
          svg += `<path class="bar" data-i="${i}" d="M${x},${y0}V${y0 - h + r}Q${x},${y0 - h} ${x + r},${y0 - h}H${x + bw - r}Q${x + bw},${y0 - h} ${x + bw},${y0 - h + r}V${y0}Z"/>`;
        }
        svg += `<rect class="hit" data-i="${i}" x="${m.l + i * pas}" y="${m.t}" width="${pas}" height="${ih}"/>`;
      });
      indicesX.forEach((i) => {
        if (!points[i]) return;
        const anchor = i === 0 ? 'start' : i === n - 1 ? 'end' : 'middle';
        const x = i === 0 ? m.l : i === n - 1 ? W - m.r : m.l + i * pas + pas / 2;
        svg += `<text class="axis" x="${x}" y="${hauteur - 6}" text-anchor="${anchor}">${esc(jourCourt(points[i].jour))}</text>`;
      });
      svg += '</svg>';
      conteneur.innerHTML = `${svg}<div class="tip"></div>`;
      const tip = $('.tip', conteneur);
      $$('.hit', conteneur).forEach((hit) => {
        hit.addEventListener('mouseenter', () => {
          const i = Number(hit.dataset.i);
          const p = points[i];
          const v = Number(p[cle]) || 0;
          $$('.bar', conteneur).forEach((b) => b.classList.toggle('on', b.dataset.i === String(i)));
          tip.innerHTML = `${esc(jour(p.jour))}<br><b>${esc(format(v))}</b>`;
          const echelle = conteneur.clientWidth / W;
          tip.style.left = `${(m.l + i * pas + pas / 2) * echelle}px`;
          tip.style.top = `${y(v)}px`;
          tip.classList.add('on');
        });
        hit.addEventListener('mouseleave', () => {
          tip.classList.remove('on');
          $$('.bar', conteneur).forEach((b) => b.classList.remove('on'));
        });
      });
    };
    dessiner();
    redessins.push(dessiner);
  }

  const barresH = (lignes, cleLibelle, cleValeur, libelles = {}) => {
    const max = Math.max(1, ...lignes.map((l) => Number(l[cleValeur]) || 0));
    if (!lignes.length) return '<p class="muted small">Rien sur la période.</p>';
    return lignes.map((l) => `<div class="hbar"><span>${esc(libelles[l[cleLibelle]] || l[cleLibelle])}</span>
      <div class="track"><div class="fill" style="width:${(100 * (Number(l[cleValeur]) || 0)) / max}%"></div></div>
      <b class="num" style="text-align:right">${nb(l[cleValeur])}</b></div>`).join('');
  };

  // --- Morceaux d'interface ------------------------------------------------------------------------
  const kpi = (label, valeur, sous = '', icone = 'chart', ton = '') => `<div class="card kpi ${ton}">
      <div class="label"><span class="ico">${ico(icone)}</span>${esc(label)}</div>
      <div class="value num">${valeur}</div>${sous ? `<div class="sub">${sous}</div>` : ''}</div>`;
  const montant = (n) => `${nb(n)}<small>FCFA</small>`;

  function tableau(colonnes, lignes, { lien, vide = 'Aucun résultat.' } = {}) {
    if (!lignes.length) return `<div class="empty">${esc(vide)}</div>`;
    return `<div class="table-wrap"><table><thead><tr>${colonnes.map((c) => `<th class="${c.cl || ''}">${esc(c.t)}</th>`).join('')}</tr></thead>
      <tbody>${lignes.map((l) => `<tr ${lien ? `class="link" data-href="${esc(lien(l))}"` : ''}>${colonnes.map((c) => `<td class="${c.cl || ''}">${c.f(l)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
  }
  const pager = (res) => {
    const de = res.total ? (res.page - 1) * res.taille + 1 : 0;
    const a = Math.min(res.total, res.page * res.taille);
    return `<div class="pager"><span>${nb(de)}–${nb(a)} sur ${nb(res.total)}</span><div class="row">
      <button class="btn ghost sm" data-page="${res.page - 1}" ${res.page <= 1 ? 'disabled' : ''}>Précédent</button>
      <button class="btn ghost sm" data-page="${res.page + 1}" ${a >= res.total ? 'disabled' : ''}>Suivant</button></div></div>`;
  };
  const brancherPager = (el, etat, recharger) => $$('[data-page]', el).forEach((b) => {
    b.onclick = () => { etat.page = Number(b.dataset.page); recharger(); };
  });
  const personne = (nom, sous = '') => `<div class="who"><span class="avatar">${esc(initiales(nom))}</span><div><b>${esc(nom)}</b>${sous ? `<span>${sous}</span>` : ''}</div></div>`;
  const squelette = (n = 4, h = 110) => `<div class="grid kpis">${'<div class="skeleton" style="min-height:'.concat(h, 'px"></div>').repeat(n)}</div>`;
  const peut = (module) => moi?.modules.includes(module);
  const retour = (href, texte) => `<a class="btn ghost sm" href="${href}">${ico('back').replace('<svg', '<svg width="16" height="16"')}${esc(texte)}</a>`;

  // --- Connexion --------------------------------------------------------------------------------------
  function pageConnexion(msg = '') {
    $('#racine').innerHTML = `<div class="login"><div class="login-card">
      <div class="logo"><span class="logo-mark">${ico('route')}</span><div>MboaRide<small>Console d'administration</small></div></div>
      <h1>Bienvenue</h1>
      <p>Réservée à l'équipe MboaRide. Connectez-vous avec votre compte de l'application.</p>
      <div class="error" ${msg ? '' : 'hidden'}>${esc(msg)}</div>
      <form id="connexion">
        <label class="field"><span>E-mail ou téléphone</span><input name="identifiant" autocomplete="username" required></label>
        <label class="field"><span>Mot de passe</span><input name="mdp" type="password" autocomplete="current-password" required></label>
        <button class="btn block" type="submit">Se connecter</button>
      </form>
      <div class="login-demo" hidden><h3>Démonstration</h3><p class="small muted" style="margin:4px 0 0">Entrer sans mot de passe avec un compte de l'équipe.</p><div class="chips"></div></div>
    </div></div>`;
    const form = $('#connexion');
    const err = $('.login-card .error');
    form.onsubmit = async (ev) => {
      ev.preventDefault();
      const btn = $('button', form);
      btn.disabled = true;
      err.hidden = true;
      try {
        let r;
        try {
          r = await fetch(`${AUTH}/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ identifier: form.identifiant.value.trim(), password: form.mdp.value }) });
        } catch {
          throw new Error(`Le service de connexion ne répond pas (${AUTH}) : lancez l'API Node.`);
        }
        const data = await r.json().catch(() => null);
        if (!r.ok) throw new Error(messageErreur(data) || 'Identifiants invalides');
        garder({ jeton: data.access_token, refresh: data.refresh_token });
        await demarrer();
      } catch (e) {
        err.textContent = e.message;
        err.hidden = false;
        btn.disabled = false;
      }
    };
    fetch('/api/admin/demo/comptes').then((r) => (r.ok ? r.json() : [])).then((comptes) => {
      if (!comptes.length) return;
      const zone = $('.login-demo');
      zone.hidden = false;
      $('.chips', zone).innerHTML = comptes.map((c) => `<button class="btn soft sm" data-uid="${c.id_utilisateur}">${esc(c.prenom)} ${esc(c.nom)} · ${esc(PASTILLES.role[c.role][1])}</button>`).join('');
      $$('[data-uid]', zone).forEach((b) => { b.onclick = () => { garder({ uid: Number(b.dataset.uid) }); demarrer(); }; });
    }).catch(() => {});
  }

  // --- Cadre de l'application ----------------------------------------------------------------------
  const ROUTES = [
    { id: 'tableau', titre: 'Tableau de bord', icone: 'home', section: 'Pilotage' },
    { id: 'utilisateurs', titre: 'Utilisateurs', icone: 'users', section: 'Opérations' },
    { id: 'agrements', titre: 'Agréments', icone: 'shield', section: 'Opérations' },
    { id: 'trajets', titre: 'Trajets et courses', icone: 'route', section: 'Opérations' },
    { id: 'paiements', titre: 'Paiements', icone: 'card', section: 'Argent' },
    { id: 'finances', titre: 'Finances', icone: 'chart', section: 'Argent' },
    { id: 'equipe', module: 'administrateurs', titre: 'Équipe MboaRide', icone: 'key', section: 'Réglages' },
    { id: 'journal', titre: "Journal d'audit", icone: 'list', section: 'Réglages' },
  ];

  function cadre() {
    const visibles = ROUTES.filter((r) => peut(r.module || r.id));
    let section = '';
    const nav = visibles.map((r) => {
      const titre = r.section !== section ? `<div class="nav-section">${esc(r.section)}</div>` : '';
      section = r.section;
      return `${titre}<a href="#/${r.id}" data-route="${r.id}">${ico(r.icone)}<span>${esc(r.titre)}</span>${r.id === 'agrements' ? '<span class="badge" id="badge-agrements" hidden></span>' : ''}</a>`;
    }).join('');
    const nom = `${moi.prenom} ${moi.nom}`;
    $('#racine').innerHTML = `<div class="app">
      <aside class="sidebar">
        <div class="logo"><span class="logo-mark">${ico('route')}</span><div>MboaRide<small>Console</small></div></div>
        <nav class="nav">${nav}</nav>
        <div class="me"><div class="me-id"><span class="avatar">${esc(initiales(nom))}</span><div><b title="${esc(nom)}">${esc(nom)}</b><span class="small muted">${esc(PASTILLES.role[moi.role][1])}</span></div></div>
          <div class="me-actions"><button class="btn ghost sm" id="theme" title="Thème clair ou sombre">${boutonTheme()}</button>
          <button class="btn ghost sm" id="sortir">${ico('out').replace('<svg', '<svg width="15" height="15"')}Sortir</button></div></div>
      </aside>
      <div class="main"><div class="topbar"><button class="btn ghost sm" id="menu" aria-label="Menu">${ico('menu').replace('<svg', '<svg width="18" height="18"')}</button>
        <div class="logo"><span class="logo-mark" style="width:30px;height:30px">${ico('route')}</span>MboaRide</div></div>
        <div id="vue"></div></div>
    </div>`;
    $('#sortir').onclick = () => deconnexion('Vous êtes déconnecté.');
    $('#theme').onclick = (ev) => {
      basculerTheme();
      ev.currentTarget.innerHTML = boutonTheme();
    };
    $('#menu').onclick = () => $('.app').classList.toggle('menu-open');
    $('.nav').addEventListener('click', () => $('.app').classList.remove('menu-open'));
    $('#racine').addEventListener('click', (ev) => {
      const tr = ev.target.closest('tr.link');
      if (tr && !ev.target.closest('button, a')) location.hash = tr.dataset.href;
    });
    majBadge();
  }

  async function majBadge() {
    const b = $('#badge-agrements');
    if (!b) return;
    try {
      const tb = await api('/api/admin/tableau-de-bord?jours=1');
      const n = tb.indicateurs.agrements_en_attente;
      b.textContent = n;
      b.hidden = !n;
    } catch { /* indicatif seulement */ }
  }

  let rendu = 0;
  const vue = (html) => { redessins = []; $('#vue').innerHTML = `<div class="page">${html}</div>`; window.scrollTo(0, 0); };
  const actuel = (n) => n === rendu;

  async function router() {
    if (!moi) return;
    const [id = 'tableau', arg] = location.hash.replace(/^#\/?/, '').split('/');
    const route = ROUTES.find((r) => r.id === id && peut(r.module || r.id)) || ROUTES.find((r) => peut(r.module || r.id));
    $$('.nav a').forEach((a) => a.classList.toggle('active', a.dataset.route === route.id));
    document.title = `${route.titre} · MboaRide Console`;
    const n = ++rendu;
    const ancre = location.hash;
    try {
      await PAGES[route.id](n, arg);
    } catch (e) {
      if (moi && location.hash === ancre && e.message !== 'Session expirée') {
        vue(`<div class="card"><div class="error" style="margin:0">${esc(e.message)}</div></div>`);
      }
    }
  }
  // Erreur d'un filtre ou d'une pagination (hors premier affichage) : un message suffit.
  window.addEventListener('unhandledrejection', (ev) => {
    const msg = ev.reason?.message;
    if (msg && msg !== 'Session expirée') toast(msg, true);
  });

  async function demarrer() {
    try {
      moi = await api('/api/admin/moi');
    } catch (e) {
      garder(null);
      pageConnexion(e.message === 'Session expirée' ? '' : e.message);
      return;
    }
    cadre();
    router();
  }
  window.addEventListener('hashchange', router);

  // --- Pages --------------------------------------------------------------------------------------------
  const E = {};   // filtres de chaque page, gardés en revenant d'une fiche

  async function pageTableau(n) {
    const etat = E.tableau ||= { jours: 30 };
    vue(`<div class="page-head"><div><h1>Bonjour ${esc(moi.prenom)}</h1><p>L'activité de MboaRide en un coup d'œil.</p></div>
      <div class="tabs" id="periode">${[7, 30, 90].map((j) => `<button data-j="${j}" class="${j === etat.jours ? 'on' : ''}">${j} jours</button>`).join('')}</div></div>
      <div id="contenu">${squelette(8)}</div>`);
    $$('#periode button').forEach((b) => { b.onclick = () => { etat.jours = Number(b.dataset.j); pageTableau(++rendu); }; });
    const tb = await api(`/api/admin/tableau-de-bord?jours=${etat.jours}`);
    if (!actuel(n)) return;
    const i = tb.indicateurs;
    const sur = `sur ${tb.jours} jours`;
    $('#contenu').innerHTML = `
      <div class="grid kpis">
        ${kpi('Utilisateurs', nb(i.utilisateurs), `+${nb(i.nouveaux_utilisateurs)} ${sur}`, 'users')}
        ${kpi('Conducteurs agréés', nb(i.conducteurs_agrees), `${nb(i.agrements_en_attente)} dossier(s) à vérifier`, 'shield', i.agrements_en_attente ? 'warn' : '')}
        ${kpi('Trajets en ligne', nb(i.trajets_actifs), `${nb(i.courses_en_cours)} course(s) en cours`, 'route')}
        ${kpi('Réservations', nb(i.reservations), `${nb(i.reservations_annulees)} annulée(s) ${sur}`, 'car')}
        ${kpi('Encaissé', montant(i.encaisse_fcfa), sur, 'money')}
        ${kpi('Commission MboaRide', montant(i.commission_fcfa), sur, 'chart')}
        ${kpi('Versé aux conducteurs', montant(i.verse_fcfa), sur, 'wallet')}
        ${kpi('En séquestre', montant(i.sequestre_fcfa), 'en attente de fin de course', 'lock', 'info')}
      </div>
      <div class="grid cols-2 mt">
        <div class="card"><div class="card-head"><h2>Encaissé par jour</h2><span class="muted small">FCFA</span></div><div class="chart" id="g-encaisse"></div></div>
        <div class="card"><div class="card-head"><h2>Réservations par jour</h2></div><div class="chart" id="g-resa"></div></div>
      </div>
      <div class="grid cols-3 mt">
        <div class="card"><div class="card-head"><h2>À traiter</h2></div><div class="list" id="a-traiter"></div></div>
        <div class="card"><div class="card-head"><h2>Inscriptions par jour</h2></div><div class="chart" id="g-inscr"></div></div>
        <div class="card"><div class="card-head"><h2>Santé</h2></div>
          <dl class="dl">
            <dt>Remboursé</dt><dd class="num">${fcfa(i.rembourse_fcfa)}</dd>
            <dt>Paiements échoués</dt><dd class="num">${nb(i.paiements_echoues)}</dd>
            <dt>Soldes des portefeuilles</dt><dd class="num">${fcfa(i.soldes_portefeuilles_fcfa)}</dd>
            <dt>Note moyenne</dt><dd class="num">${i.note_moyenne ? `${Number(i.note_moyenne).toLocaleString('fr-FR')} / 5` : '—'}</dd>
            <dt>Signalements graves</dt><dd class="num">${nb(i.signalements_graves)}</dd>
            <dt>Comptes suspendus</dt><dd class="num">${nb(i.comptes_suspendus)}</dd>
          </dl>
          <h3 class="mt-lg" style="margin-bottom:8px">Réservations par statut</h3>
          ${barresH(tb.reservations_par_statut, 'statut', 'n', { confirmee: 'Confirmées', terminee: 'Terminées', annulee: 'Annulées' })}
        </div>
      </div>`;
    barres($('#g-encaisse'), tb.serie, 'encaisse_fcfa', fcfa);
    barres($('#g-resa'), tb.serie, 'reservations', (v) => `${nb(v)} réservation(s)`);
    barres($('#g-inscr'), tb.serie, 'inscriptions', (v) => `${nb(v)} inscription(s)`, 160);
    const t = tb.a_traiter;
    const items = [
      ...t.agrements.map((a) => ({ ico: 'shield', ton: 'warn', txt: `${a.prenom} ${a.nom}`, sous: `${a.pieces} pièce(s) à vérifier depuis le ${jour(a.depuis)}`, href: peut('agrements') ? '#/agrements' : null })),
      ...t.signalements.map((s) => ({ ico: 'alert', ton: 'bad', txt: `Signalement sur ${s.evalue}`, sous: `${s.auteur} · ${esc(s.commentaire || 'sans commentaire')}`, href: peut('utilisateurs') ? `#/utilisateurs/${s.id_evalue}` : null })),
      ...t.paiements_echoues.map((p) => ({ ico: 'card', ton: 'bad', txt: `Paiement échoué · ${p.passager}`, sous: `${fcfa(p.montant_fcfa)} · ${esc(p.motif_echec || '')}`, href: peut('paiements') ? '#/paiements' : null })),
    ];
    $('#a-traiter').innerHTML = items.length ? items.slice(0, 8).map((it) => `<div class="item"><span class="avatar" style="background:var(--${it.ton}-soft);color:var(--${it.ton})">${ico(it.ico).replace('<svg', '<svg width="16" height="16"')}</span>
      <div><b>${it.href ? `<a href="${it.href}">${esc(it.txt)}</a>` : esc(it.txt)}</b><div class="small muted">${it.sous}</div></div></div>`).join('')
      : '<p class="muted">Rien en attente. Tout est à jour.</p>';
    majBadge();
  }

  // Utilisateurs ---------------------------------------------------------------------------------------
  async function pageUtilisateurs(n, arg) {
    if (arg) return ficheUtilisateur(n, Number(arg));
    const etat = E.utilisateurs ||= { q: '', role: '', statut: '', page: 1 };
    vue(`<div class="page-head"><div><h1>Utilisateurs</h1><p>Passagers, conducteurs et équipe MboaRide.</p></div></div>
      <div class="card"><div class="filters">
        <input type="search" id="q" placeholder="Nom, e-mail ou téléphone" value="${esc(etat.q)}">
        <select id="role"><option value="">Tous les profils</option><option value="conducteur">Conducteurs</option><option value="passager">Passagers</option><option value="admin">Équipe MboaRide</option></select>
        <select id="statut"><option value="">Tous les comptes</option><option value="actif">Actifs</option><option value="suspendu">Suspendus</option><option value="agrement_en_attente">Agrément en vérification</option></select>
      </div><div id="resultats">${squelette(1, 240)}</div></div>`);
    $('#role').value = etat.role;
    $('#statut').value = etat.statut;
    const charger = async () => {
      const m = ++rendu;
      const res = await api(`/api/admin/utilisateurs?${qs({ q: etat.q, role: etat.role, statut: etat.statut, page: etat.page })}`);
      if (!actuel(m)) return;
      const el = $('#resultats');
      el.innerHTML = tableau([
        { t: 'Utilisateur', f: (u) => personne(`${u.prenom} ${u.nom}`, esc(u.email || u.telephone)) },
        { t: 'Téléphone', f: (u) => `<span class="num">${esc(u.telephone)}</span>` },
        { t: 'Profil', f: (u) => `<div class="row">${u.est_conducteur ? pastille('agrement', u.statut_agrement) : '<span class="pill plain">Passager</span>'}${u.role_admin ? pastille('role', u.role_admin) : ''}</div>` },
        { t: 'Trajets', cl: 'r', f: (u) => `<span class="num">${nb(u.trajets_passager + u.trajets_conducteur)}</span>` },
        { t: 'Inscrit le', f: (u) => jour(u.cree_le) },
        { t: 'Compte', f: (u) => (u.suspendu_le ? '<span class="pill bad">Suspendu</span>' : '<span class="pill good">Actif</span>') },
      ], res.lignes, { lien: (u) => `#/utilisateurs/${u.id_utilisateur}`, vide: 'Aucun utilisateur ne correspond.' }) + pager(res);
      brancherPager(el, etat, charger);
    };
    let attente;
    $('#q').oninput = (ev) => { clearTimeout(attente); attente = setTimeout(() => { etat.q = ev.target.value.trim(); etat.page = 1; charger(); }, 250); };
    $('#role').onchange = (ev) => { etat.role = ev.target.value; etat.page = 1; charger(); };
    $('#statut').onchange = (ev) => { etat.statut = ev.target.value; etat.page = 1; charger(); };
    await charger();
  }

  async function ficheUtilisateur(n, uid) {
    vue(`${retour('#/utilisateurs', 'Utilisateurs')}<div id="fiche" class="mt">${squelette(3, 160)}</div>`);
    const f = await api(`/api/admin/utilisateurs/${uid}`);
    if (!actuel(n)) return;
    const u = f.utilisateur;
    const nom = `${u.prenom} ${u.nom}`;
    const suspendu = Boolean(u.suspendu_le);
    $('#fiche').innerHTML = `
      <div class="card"><div class="row" style="gap:18px">
        <span class="avatar lg">${esc(initiales(nom))}</span>
        <div style="flex:1;min-width:200px"><h1>${esc(nom)}</h1>
          <div class="row mt" style="margin-top:8px">${suspendu ? '<span class="pill bad">Compte suspendu</span>' : '<span class="pill good">Compte actif</span>'}
          ${u.est_conducteur ? pastille('agrement', u.statut_agrement) : '<span class="pill plain">Passager</span>'}${f.role_admin ? pastille('role', f.role_admin) : ''}</div>
          ${suspendu ? `<p class="small" style="color:var(--bad);margin:10px 0 0">Suspendu le ${quand(u.suspendu_le)} : ${esc(u.motif_suspension)}</p>` : ''}</div>
        <div class="row">${suspendu ? '<button class="btn" id="reactiver">Réactiver le compte</button>' : '<button class="btn danger" id="suspendre">Suspendre le compte</button>'}</div>
      </div></div>
      <div class="grid cols-3 mt">
        <div class="card"><div class="card-head"><h2>Coordonnées</h2></div><dl class="dl">
          <dt>Téléphone</dt><dd class="num">${esc(u.telephone)}</dd><dt>E-mail</dt><dd>${esc(u.email || '—')}</dd>
          <dt>Inscrit le</dt><dd>${jour(u.cree_le)}</dd><dt>Réservation</dt><dd>${u.mode_reservation === 'autonome' ? 'Automatique' : 'Manuelle'}</dd>
          <dt>Priorité</dt><dd>${u.priorite === 'prix' ? 'Le prix' : "L'heure"}</dd>
          <dt>Organisations</dt><dd>${f.organisations.map((o) => `${esc(o.nom)}${o.role === 'administrateur' ? ' (admin)' : ''}`).join(', ') || '—'}</dd></dl></div>
        <div class="card"><div class="card-head"><h2>Portefeuille</h2><b class="num">${fcfa(f.portefeuille.solde_fcfa)}</b></div>
          <div class="list">${f.portefeuille.mouvements.map((m) => `<div class="item"><div><b class="small">${esc(m.libelle)}</b><div class="small muted">${quand(m.cree_le)}</div></div>
            <b class="num small" style="color:${m.montant_fcfa > 0 ? 'var(--good)' : 'var(--ink-2)'}">${m.montant_fcfa > 0 ? '+' : ''}${nb(m.montant_fcfa)}</b></div>`).join('') || '<p class="muted small">Aucun mouvement.</p>'}</div></div>
        <div class="card"><div class="card-head"><h2>Évaluations reçues</h2><b class="num">${f.evaluations.note_moyenne ? `${Number(f.evaluations.note_moyenne).toLocaleString('fr-FR')} / 5` : '—'}</b></div>
          <p class="small muted" style="margin:0 0 8px">${nb(f.evaluations.nombre)} évaluation(s)${f.evaluations.signalements_graves ? ` · <b style="color:var(--bad)">${nb(f.evaluations.signalements_graves)} signalement(s) grave(s)</b>` : ''}</p>
          <div class="list">${f.evaluations.dernieres.map((e) => `<div class="item"><div><b class="small">${'★'.repeat(e.note)}${'☆'.repeat(5 - e.note)} · ${esc(e.auteur)}</b>
            <div class="small muted">${esc(e.commentaire || 'Sans commentaire')}</div></div>${e.signalement_grave ? '<span class="pill bad">Grave</span>' : ''}</div>`).join('') || '<p class="muted small">Aucune évaluation.</p>'}</div></div>
      </div>
      ${u.est_conducteur || f.documents.some((d) => d.statut !== 'manquant') ? `<div class="card mt"><div class="card-head"><h2>Conducteur</h2>${peut('agrements') ? '<a href="#/agrements" class="small">Vérifier les pièces</a>' : ''}</div>
        <p class="muted small" style="margin:0">${f.vehicules.map((v) => `${esc(v.marque_modele)} · ${esc(v.immatriculation)} · ${v.places_passagers} places${v.climatise ? ' · climatisé' : ''}`).join('<br>') || 'Aucun véhicule enregistré.'}</p>
        <div class="docs">${f.documents.map((d) => `<div class="doc"><div class="row"><b class="small">${esc(d.libelle)}</b>${pastille('piece', d.statut)}</div>
          <span class="small muted">${d.statut === 'valide' && d.expire_le ? `Valable jusqu'au ${jour(d.expire_le)}` : d.motif_refus ? esc(d.motif_refus) : d.depose_le ? `Déposée le ${jour(d.depose_le)}` : ''}</span></div>`).join('')}</div>
        ${f.trajets_conducteur.length ? `<h3 class="mt-lg" style="margin-bottom:6px">Trajets publiés</h3>${tableau([
          { t: 'Trajet', f: (t) => `<b>${esc(t.depart_libelle)} → ${esc(t.arrivee_libelle)}</b>` },
          { t: 'Horaire', f: (t) => esc(horaire(t)) },
          { t: 'Statut', f: (t) => pastille('trajet', t.statut === 'annule' ? 'retire' : t.statut === 'termine' ? 'passe' : 'actif') },
        ], f.trajets_conducteur, { lien: (t) => `#/trajets/${t.id_trajet}` })}` : ''}</div>` : ''}
      <div class="grid cols-2 mt">
        <div class="card"><div class="card-head"><h2>Réservations (passager)</h2></div>${tableau([
          { t: 'Trajet', f: (r) => `<b>${esc(r.depart_libelle)} → ${esc(r.arrivee_libelle)}</b><div class="small muted">avec ${esc(r.conducteur)}</div>` },
          { t: 'Date', f: (r) => jour(r.date_trajet) },
          { t: 'Prix', cl: 'r', f: (r) => `<span class="num">${fcfa(r.prix_fcfa)}</span>` },
          { t: 'Statut', f: (r) => pastille('reservation', r.statut) },
        ], f.reservations, { vide: 'Aucune réservation.' })}</div>
        <div class="card"><div class="card-head"><h2>Historique d'administration</h2></div>
          <div class="list">${f.journal.map((j) => `<div class="item"><div><b class="small">${esc(j.resume)}</b><div class="small muted">${quand(j.cree_le)} · ${esc(j.par || 'ligne de commande')}</div></div></div>`).join('') || '<p class="muted small">Aucune action sur ce compte.</p>'}</div></div>
      </div>`;
    $('#suspendre')?.addEventListener('click', async () => {
      const ok = await demander({
        titre: `Suspendre ${nom} ?`, danger: true, bouton: 'Suspendre',
        texte: "La personne ne pourra plus utiliser l'application. Elle est prévenue et le motif apparaît dans le journal.",
        champs: [{ nom: 'motif', label: 'Motif', type: 'textarea', requis: true, minlength: 3, aide: 'Ce que la personne lira' },
          ...(u.est_conducteur ? [{ nom: 'retirer_trajets', label: 'Retirer ses trajets en ligne (les passagers sont remboursés et réaffectés)', type: 'checkbox', valeur: true }] : [])],
        action: (v) => api(`/api/admin/utilisateurs/${uid}/suspension`, { methode: 'POST', corps: { motif: v.motif, retirer_trajets: v.retirer_trajets ?? false } }),
      });
      if (ok) { toast(`Compte de ${nom} suspendu${ok.trajets_retires ? `, ${ok.trajets_retires} trajet(s) retiré(s)` : ''}.`); router(); }
    });
    $('#reactiver')?.addEventListener('click', async () => {
      const ok = await demander({
        titre: `Réactiver ${nom} ?`, bouton: 'Réactiver',
        champs: [{ nom: 'motif', label: 'Motif', type: 'textarea', requis: true, minlength: 3 }],
        action: (v) => api(`/api/admin/utilisateurs/${uid}/reactivation`, { methode: 'POST', corps: v }),
      });
      if (ok) { toast(`Compte de ${nom} réactivé.`); router(); }
    });
  }

  // Agréments --------------------------------------------------------------------------------------------
  async function pageAgrements(n) {
    const etat = E.agrements ||= { statut: 'en_attente', q: '', page: 1 };
    const onglets = [['en_attente', 'À vérifier'], ['actif', 'Agréés'], ['suspendu', 'Suspendus'], ['tous', 'Tous']];
    vue(`<div class="page-head"><div><h1>Agréments</h1><p>Vérifiez les pièces des conducteurs avant qu'ils ne publient des trajets.</p></div>
      <div class="tabs" id="onglets">${onglets.map(([v, l]) => `<button data-v="${v}" class="${v === etat.statut ? 'on' : ''}">${l}</button>`).join('')}</div></div>
      <div class="filters"><input type="search" id="q" placeholder="Nom ou téléphone" value="${esc(etat.q)}"></div>
      <div id="resultats" class="stack">${squelette(1, 200)}</div>`);
    const charger = async () => {
      const m = ++rendu;
      const res = await api(`/api/admin/agrements?${qs({ statut: etat.statut, q: etat.q, page: etat.page, taille: 10 })}`);
      if (!actuel(m)) return;
      const el = $('#resultats');
      el.innerHTML = (res.lignes.length ? res.lignes.map((c) => {
        const nom = `${c.prenom} ${c.nom}`;
        return `<div class="card" data-uid="${c.id_utilisateur}">
          <div class="row"><a href="#/utilisateurs/${c.id_utilisateur}" style="color:inherit">${personne(nom, `${esc(c.telephone)}${c.vehicule ? ` · ${esc(c.vehicule.marque_modele)} ${esc(c.vehicule.immatriculation)}` : ''}`)}</a>
            <span class="spacer"></span>${pastille('agrement', c.statut_agrement)}
            ${c.en_attente_depuis ? `<span class="small muted">en attente depuis le ${jour(c.en_attente_depuis)}</span>` : ''}</div>
          <div class="docs">${c.documents.map((d) => `<div class="doc"><div class="row"><b class="small">${esc(d.libelle)}</b>${pastille('piece', d.statut)}</div>
            <span class="small muted">${d.statut === 'valide' ? `Valable jusqu'au ${jour(d.expire_le)}${d.verifie_par ? ` · ${esc(d.verifie_par)}` : ''}`
              : d.statut === 'refuse' ? `Refusée : ${esc(d.motif_refus || '')}` : d.depose_le ? `Déposée le ${jour(d.depose_le)}` : 'Pas encore déposée'}</span>
            ${d.statut !== 'manquant' ? `<div class="actions">${d.statut !== 'valide' ? `<button class="btn soft sm" data-valider="${d.type}">Valider</button>` : ''}
              ${d.statut !== 'refuse' ? `<button class="btn ghost sm" data-refuser="${d.type}">Refuser</button>` : ''}</div>` : ''}</div>`).join('')}</div>
          <div class="row mt">${c.statut_agrement === 'actif' ? '<button class="btn ghost sm" data-suspendre>Suspendre l\'agrément</button>'
            : c.statut_agrement === 'suspendu' ? '<button class="btn soft sm" data-retablir>Rétablir l\'agrément</button>' : ''}</div>
        </div>`;
      }).join('') : `<div class="card empty">${etat.statut === 'en_attente' ? 'Aucune pièce à vérifier. Tout est à jour.' : 'Aucun conducteur.'}</div>`)
        + (res.total > res.taille ? pager(res) : '');
      brancherPager(el, etat, charger);
      const ligne = (b) => res.lignes.find((c) => c.id_utilisateur === Number(b.closest('[data-uid]').dataset.uid));
      const decider = async (c, type, decision, champs, titre, bouton, danger) => {
        const libelle = c.documents.find((d) => d.type === type).libelle;
        const ok = await demander({
          titre: `${titre} · ${libelle}`, texte: `${esc(c.prenom)} ${esc(c.nom)}`, bouton, danger, champs,
          action: (v) => api(`/api/admin/agrements/${c.id_utilisateur}/documents/${type}`, { methode: 'POST', corps: { decision, ...v } }),
        });
        if (!ok) return;
        toast(ok.statut_agrement === 'actif' && c.statut_agrement !== 'actif' ? `${c.prenom} est maintenant agréé·e : il ou elle peut publier ses trajets.`
          : `${libelle} ${decision === 'valide' ? 'validée' : 'refusée'}.`);
        majBadge();
        charger();
      };
      const dansUnAn = new Date(); dansUnAn.setFullYear(dansUnAn.getFullYear() + 1);
      const demain = new Date(); demain.setDate(demain.getDate() + 1);
      $$('[data-valider]', el).forEach((b) => { b.onclick = () => decider(ligne(b), b.dataset.valider, 'valide',
        [{ nom: 'expire_le', label: "Valable jusqu'au", type: 'date', valeur: iso(dansUnAn), min: iso(demain), requis: true }], 'Valider', 'Valider'); });
      $$('[data-refuser]', el).forEach((b) => { b.onclick = () => decider(ligne(b), b.dataset.refuser, 'refuse',
        [{ nom: 'motif', label: 'Motif du refus (envoyé au conducteur)', type: 'textarea', requis: true, aide: 'Ex. : photo floue, document expiré' }], 'Refuser', 'Refuser', true); });
      $$('[data-suspendre], [data-retablir]', el).forEach((b) => {
        b.onclick = async () => {
          const c = ligne(b);
          const suspendre = b.hasAttribute('data-suspendre');
          const ok = await demander({
            titre: suspendre ? `Suspendre l'agrément de ${c.prenom} ?` : `Rétablir l'agrément de ${c.prenom} ?`,
            texte: suspendre ? 'Ses trajets ne seront plus proposés aux passagers.' : 'Les quatre pièces doivent être valides.',
            bouton: suspendre ? 'Suspendre' : 'Rétablir', danger: suspendre,
            champs: [{ nom: 'motif', label: 'Motif', type: 'textarea', requis: true, minlength: 3 },
              ...(suspendre ? [{ nom: 'retirer_trajets', label: 'Retirer ses trajets en ligne (passagers remboursés et réaffectés)', type: 'checkbox', valeur: true }] : [])],
            action: (v) => api(`/api/admin/agrements/${c.id_utilisateur}/statut`, { methode: 'POST', corps: { statut: suspendre ? 'suspendu' : 'actif', ...v } }),
          });
          if (ok) { toast(suspendre ? 'Agrément suspendu.' : 'Agrément rétabli.'); charger(); }
        };
      });
    };
    $$('#onglets button').forEach((b) => { b.onclick = () => { etat.statut = b.dataset.v; etat.page = 1; $$('#onglets button').forEach((x) => x.classList.toggle('on', x === b)); charger(); }; });
    let attente;
    $('#q').oninput = (ev) => { clearTimeout(attente); attente = setTimeout(() => { etat.q = ev.target.value.trim(); etat.page = 1; charger(); }, 250); };
    await charger();
  }

  // Trajets et courses -------------------------------------------------------------------------------------
  async function pageTrajets(n, arg) {
    if (arg) return ficheTrajet(n, Number(arg));
    const etat = E.trajets ||= { vue: 'trajets', etat: 'actif', type: '', q: '', page: 1, statutCourse: '' };
    vue(`<div class="page-head"><div><h1>Trajets et courses</h1><p>Les trajets publiés par les conducteurs et les courses du jour.</p></div>
      <div class="tabs" id="onglets"><button data-v="trajets">Trajets</button><button data-v="courses">Courses</button></div></div>
      <div class="card"><div class="filters" id="filtres"></div><div id="resultats">${squelette(1, 240)}</div></div>`);
    const filtres = () => {
      $$('#onglets button').forEach((b) => b.classList.toggle('on', b.dataset.v === etat.vue));
      $('#filtres').innerHTML = etat.vue === 'trajets'
        ? `<input type="search" id="q" placeholder="Lieu ou conducteur" value="${esc(etat.q)}">
           <select id="etat"><option value="">Tous les états</option><option value="actif">En ligne</option><option value="retire">Retirés</option><option value="passe">Passés</option></select>
           <select id="type"><option value="">Urbain et interurbain</option><option value="urbain">Urbain</option><option value="interurbain">Interurbain</option></select>`
        : `<select id="statut-course"><option value="">Toutes les courses</option><option value="en_cours">En cours</option><option value="arrivee">Arrivées, fin à valider</option><option value="reglee">Réglées</option></select>`;
      if (etat.vue === 'trajets') {
        $('#etat').value = etat.etat;
        $('#type').value = etat.type;
        let attente;
        $('#q').oninput = (ev) => { clearTimeout(attente); attente = setTimeout(() => { etat.q = ev.target.value.trim(); etat.page = 1; charger(); }, 250); };
        $('#etat').onchange = (ev) => { etat.etat = ev.target.value; etat.page = 1; charger(); };
        $('#type').onchange = (ev) => { etat.type = ev.target.value; etat.page = 1; charger(); };
      } else {
        $('#statut-course').value = etat.statutCourse;
        $('#statut-course').onchange = (ev) => { etat.statutCourse = ev.target.value; etat.page = 1; charger(); };
      }
    };
    const charger = async () => {
      const m = ++rendu;
      const el = $('#resultats');
      if (etat.vue === 'trajets') {
        const res = await api(`/api/admin/trajets?${qs({ etat: etat.etat, type_trajet: etat.type, q: etat.q, page: etat.page })}`);
        if (!actuel(m)) return;
        el.innerHTML = tableau([
          { t: 'Trajet', f: (t) => `<b>${esc(t.depart_libelle)} → ${esc(t.arrivee_libelle)}</b><div class="small muted">${t.type_trajet === 'interurbain' ? 'Interurbain' : 'Urbain'}</div>` },
          { t: 'Conducteur', f: (t) => personne(t.conducteur) },
          { t: 'Horaire', f: (t) => esc(horaire(t)) },
          { t: 'Places', cl: 'r', f: (t) => `<span class="num">${t.places_offertes}</span>` },
          { t: 'À venir', cl: 'r', f: (t) => `<span class="num">${nb(t.reservations_a_venir)}</span>` },
          { t: 'État', f: (t) => pastille('trajet', t.etat) },
        ], res.lignes, { lien: (t) => `#/trajets/${t.id_trajet}`, vide: 'Aucun trajet.' }) + pager(res);
        brancherPager(el, etat, charger);
      } else {
        const res = await api(`/api/admin/courses?${qs({ statut: etat.statutCourse, page: etat.page })}`);
        if (!actuel(m)) return;
        el.innerHTML = tableau([
          { t: 'Course', f: (c) => `<b>${esc(c.depart_libelle)} → ${esc(c.arrivee_libelle)}</b><div class="small muted">${jour(c.date_trajet)}</div>` },
          { t: 'Conducteur', f: (c) => personne(c.conducteur) },
          { t: 'Démarrée', f: (c) => quand(c.demarree_le) },
          { t: 'Fins validées', cl: 'r', f: (c) => `<span class="num">${c.fins_validees} / ${c.passagers}</span>` },
          { t: 'Statut', f: (c) => pastille('course', c.statut) },
        ], res.lignes, { lien: (c) => `#/trajets/${c.id_trajet}`, vide: 'Aucune course.' }) + pager(res);
        brancherPager(el, etat, charger);
      }
    };
    $$('#onglets button').forEach((b) => { b.onclick = () => { etat.vue = b.dataset.v; etat.page = 1; filtres(); charger(); }; });
    filtres();
    await charger();
  }

  async function ficheTrajet(n, id) {
    vue(`${retour('#/trajets', 'Trajets')}<div id="fiche" class="mt">${squelette(2, 180)}</div>`);
    const f = await api(`/api/admin/trajets/${id}`);
    if (!actuel(n)) return;
    const t = f.trajet;
    $('#fiche').innerHTML = `
      <div class="card"><div class="row" style="gap:16px"><div style="flex:1;min-width:220px">
        <h1>${esc(t.depart_libelle)} → ${esc(t.arrivee_libelle)}</h1>
        <div class="row" style="margin-top:8px">${pastille('trajet', t.etat)}<span class="pill plain">${t.type_trajet === 'interurbain' ? 'Interurbain' : 'Urbain'}</span>
          <span class="muted small">${esc(horaire(t))} · ${t.places_offertes} place(s)</span></div></div>
        ${t.etat !== 'retire' ? '<button class="btn danger" id="retirer">Retirer le trajet</button>' : ''}</div>
        <dl class="dl mt-lg">
          <dt>Conducteur</dt><dd><a href="#/utilisateurs/${t.id_conducteur}">${esc(t.conducteur)}</a> · <span class="num">${esc(t.telephone_conducteur)}</span></dd>
          <dt>Véhicule</dt><dd>${esc(t.marque_modele)} · ${esc(t.immatriculation)}</dd>
          <dt>Ramassage</dt><dd>${esc(t.point_ramassage || '—')}${t.consignes_ramassage ? ` · ${esc(t.consignes_ramassage)}` : ''}</dd>
          <dt>Détour accepté</dt><dd>${Number(t.detour_max_km).toLocaleString('fr-FR')} km</dd>
          <dt>Publié le</dt><dd>${jour(t.cree_le)}</dd></dl></div>
      <div class="card mt"><div class="card-head"><h2>Réservations</h2><span class="muted small">${f.reservations.length}</span></div>${tableau([
        { t: 'Passager', f: (r) => `<a href="#/utilisateurs/${r.id_passager}">${esc(r.passager)}</a>` },
        { t: 'Date', f: (r) => `${jour(r.date_trajet)} <span class="muted small">${esc(r.prise_en_charge)}</span>` },
        { t: 'Prix', cl: 'r', f: (r) => `<span class="num">${fcfa(r.prix_fcfa)}</span>` },
        { t: 'Paiement', f: (r) => (r.paiement ? `${pastille('paiement', r.paiement)} <span class="small muted">${esc(MOYENS[r.moyen] || '')}</span>` : '—') },
        { t: 'Statut', f: (r) => `${pastille('reservation', r.statut)}${r.fin_validee_le ? ' <span class="small muted">fin validée</span>' : ''}` },
      ], f.reservations, { vide: 'Aucune réservation.' })}</div>
      <div class="grid cols-2 mt">
        <div class="card"><div class="card-head"><h2>Courses</h2></div>${tableau([
          { t: 'Date', f: (c) => jour(c.date_trajet) }, { t: 'Démarrée', f: (c) => quand(c.demarree_le) },
          { t: 'Statut', f: (c) => pastille('course', c.statut) }], f.courses, { vide: 'Aucune course démarrée.' })}</div>
        <div class="card"><div class="card-head"><h2>Dates annulées</h2></div>
          <div class="list">${f.dates_annulees.map((d) => `<div class="item"><div><b class="small">${jour(d.date_trajet)}</b><div class="small muted">${esc(d.motif || 'sans motif')}</div></div></div>`).join('') || '<p class="muted small">Aucune.</p>'}</div></div>
      </div>`;
    $('#retirer')?.addEventListener('click', async () => {
      const ok = await demander({
        titre: 'Retirer ce trajet ?', danger: true, bouton: 'Retirer',
        texte: 'Il ne sera plus proposé. Les passagers inscrits sont prévenus, remboursés et réaffectés si possible ; le conducteur reçoit le motif.',
        champs: [{ nom: 'motif', label: 'Motif (envoyé au conducteur)', type: 'textarea', requis: true, minlength: 3 }],
        action: (v) => api(`/api/admin/trajets/${id}/retrait`, { methode: 'POST', corps: v }),
      });
      if (ok) { toast(`Trajet retiré, ${ok.reservations_annulees} réservation(s) annulée(s).`); router(); }
    });
  }

  // Paiements --------------------------------------------------------------------------------------------
  async function pagePaiements(n) {
    const etat = E.paiements ||= { statut: '', moyen: '', q: '', du: '', au: '', page: 1 };
    vue(`<div class="page-head"><div><h1>Paiements</h1><p>Encaissements, séquestre, versements aux conducteurs et remboursements.</p></div>
      <button class="btn soft" id="export">${ico('download').replace('<svg', '<svg width="16" height="16"')}Exporter en CSV</button></div>
      <div class="card"><div class="filters">
        <input type="search" id="q" placeholder="Référence, passager, conducteur" value="${esc(etat.q)}">
        <select id="statut"><option value="">Tous les statuts</option><option value="sequestre">En séquestre</option><option value="reussi">Réussis</option><option value="en_attente">En attente</option><option value="echoue">Échoués</option><option value="rembourse">Remboursés</option></select>
        <select id="moyen"><option value="">Tous les moyens</option><option value="mobile_money">Mobile Money</option><option value="portefeuille">Portefeuille</option><option value="especes">Espèces</option></select>
        <input type="date" id="du" value="${esc(etat.du)}" aria-label="Du"><input type="date" id="au" value="${esc(etat.au)}" aria-label="Au">
      </div><div id="resultats">${squelette(1, 240)}</div></div>`);
    $('#statut').value = etat.statut;
    $('#moyen').value = etat.moyen;
    const filtres = () => ({ statut: etat.statut, moyen: etat.moyen, q: etat.q, du: etat.du, au: etat.au });
    const charger = async () => {
      const m = ++rendu;
      const res = await api(`/api/admin/paiements?${qs({ ...filtres(), page: etat.page })}`);
      if (!actuel(m)) return;
      const el = $('#resultats');
      el.innerHTML = tableau([
        { t: 'Référence', f: (p) => `<b class="num">${esc(p.reference_transaction || `#${p.id_paiement}`)}</b><div class="small muted">${esc(MOYENS[p.moyen] || p.moyen)}${p.operateur ? ` · ${esc(p.operateur)}` : ''}</div>` },
        { t: 'Passager → conducteur', f: (p) => `<a href="#/utilisateurs/${p.id_passager}">${esc(p.passager)}</a> → <a href="#/utilisateurs/${p.id_conducteur}">${esc(p.conducteur)}</a>
            <div class="small muted"><a href="#/trajets/${p.id_trajet}" style="color:inherit">${esc(p.trajet)}</a> · ${jour(p.date_trajet)}</div>` },
        { t: 'Montant', cl: 'r', f: (p) => `<b class="num">${fcfa(p.montant_fcfa)}</b><div class="small muted num">commission ${nb(p.commission_fcfa)}</div>` },
        { t: 'Statut', f: (p) => `${pastille('paiement', p.statut)}${p.statut === 'reussi' ? (p.verse_le ? `<div class="small muted">versé ${nb(p.montant_verse_fcfa)} le ${jour(p.verse_le)}</div>` : '<div class="small" style="color:var(--info)">en séquestre</div>')
          : p.motif_echec ? `<div class="small muted">${esc(p.motif_echec)}</div>` : ''}` },
        { t: 'Date', f: (p) => quand(p.paye_le || p.initie_le) },
        { t: '', cl: 'r', f: (p) => (p.statut === 'reussi' && !p.verse_le ? `<button class="btn ghost sm" data-rembourser="${p.id_paiement}">Rembourser</button>` : '') },
      ], res.lignes, { vide: 'Aucun paiement.' }) + pager(res);
      brancherPager(el, etat, charger);
      $$('[data-rembourser]', el).forEach((b) => {
        b.onclick = async () => {
          const p = res.lignes.find((x) => x.id_paiement === Number(b.dataset.rembourser));
          const ok = await demander({
            titre: `Rembourser ${fcfa(p.montant_fcfa)} à ${p.passager} ?`, danger: true, bouton: 'Rembourser',
            texte: `${p.moyen === 'portefeuille' ? 'Le montant est recrédité dans son portefeuille MboaRide.' : 'Le montant est renvoyé sur son compte Mobile Money.'} La réservation est annulée si elle est à venir.`,
            champs: [{ nom: 'motif', label: 'Motif (envoyé au passager)', type: 'textarea', requis: true, minlength: 3 }],
            action: (v) => api(`/api/admin/paiements/${p.id_paiement}/remboursement`, { methode: 'POST', corps: v }),
          });
          if (ok) { toast(`${fcfa(ok.montant_fcfa)} remboursés à ${p.passager}.`); charger(); }
        };
      });
    };
    let attente;
    $('#q').oninput = (ev) => { clearTimeout(attente); attente = setTimeout(() => { etat.q = ev.target.value.trim(); etat.page = 1; charger(); }, 250); };
    ['statut', 'moyen', 'du', 'au'].forEach((k) => { $(`#${k}`).onchange = (ev) => { etat[k] = ev.target.value; etat.page = 1; charger(); }; });
    $('#export').onclick = async (ev) => {
      const btn = ev.currentTarget;
      btn.disabled = true;
      try {
        const r = await api(`/api/admin/export/paiements.csv?${qs(filtres())}`, { brut: true });
        const url = URL.createObjectURL(await r.blob());
        const a = document.createElement('a');
        a.href = url;
        a.download = `paiements-${iso(new Date())}.csv`;
        a.click();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
        toast('Export prêt : le fichier s\'ouvre dans Excel.');
      } catch (e) { toast(e.message, true); } finally { btn.disabled = false; }
    };
    await charger();
  }

  // Finances ---------------------------------------------------------------------------------------------
  async function pageFinances(n) {
    const auj = new Date();
    const il30 = new Date(); il30.setDate(il30.getDate() - 29);
    const etat = E.finances ||= { du: iso(il30), au: iso(auj) };
    vue(`<div class="page-head"><div><h1>Finances</h1><p>Ce que MboaRide encaisse, garde et reverse.</p></div>
      <div class="filters" style="margin:0"><input type="date" id="du" value="${etat.du}" aria-label="Du"><span class="muted">au</span><input type="date" id="au" value="${etat.au}" aria-label="Au"></div></div>
      <div id="contenu">${squelette(8)}</div>`);
    ['du', 'au'].forEach((k) => { $(`#${k}`).onchange = (ev) => { etat[k] = ev.target.value; pageFinances(++rendu); }; });
    const f = await api(`/api/admin/finances?${qs(etat)}`);
    if (!actuel(n)) return;
    const t = f.totaux;
    $('#contenu').innerHTML = `
      <div class="grid kpis">
        ${kpi('Encaissé', montant(t.encaisse_fcfa), `${nb(t.paiements)} paiement(s)`, 'money')}
        ${kpi('Commission MboaRide', montant(t.commission_fcfa), '10 % de chaque course versée', 'chart')}
        ${kpi('Versé aux conducteurs', montant(t.verse_fcfa), 'après validation de la fin de course', 'wallet')}
        ${kpi('Remboursé', montant(t.rembourse_fcfa), 'annulations et litiges', 'card')}
        ${kpi('En séquestre', montant(t.sequestre_fcfa), 'aujourd\'hui, courses à valider', 'lock', 'info')}
        ${kpi('Soldes des portefeuilles', montant(t.soldes_portefeuilles_fcfa), 'détenus pour les utilisateurs', 'wallet', 'info')}
        ${kpi('Recharges', montant(t.recharges_fcfa), 'Mobile Money vers portefeuille', 'money')}
        ${kpi('Retraits', montant(t.retraits_fcfa), 'portefeuille vers Mobile Money', 'money')}
      </div>
      <div class="grid cols-3 mt">
        <div class="card"><div class="card-head"><h2>Encaissé</h2><span class="muted small">par jour</span></div><div class="chart" id="g1"></div></div>
        <div class="card"><div class="card-head"><h2>Commission</h2><span class="muted small">par jour</span></div><div class="chart" id="g2"></div></div>
        <div class="card"><div class="card-head"><h2>Versé aux conducteurs</h2><span class="muted small">par jour</span></div><div class="chart" id="g3"></div></div>
      </div>
      <div class="grid cols-3 mt">
        <div class="card"><div class="card-head"><h2>Par moyen de paiement</h2></div>${barresH(f.par_moyen, 'moyen', 'montant_fcfa', MOYENS)}</div>
        <div class="card"><div class="card-head"><h2>Conducteurs les mieux payés</h2></div>${tableau([
          { t: 'Conducteur', f: (c) => `<a href="#/utilisateurs/${c.id_utilisateur}">${esc(c.conducteur)}</a><div class="small muted">${nb(c.courses_payees)} course(s)</div>` },
          { t: 'Versé', cl: 'r', f: (c) => `<b class="num">${fcfa(c.verse_fcfa)}</b>` }], f.conducteurs, { vide: 'Aucun versement sur la période.' })}</div>
        <div class="card"><div class="card-head"><h2>Plus gros portefeuilles</h2></div>${tableau([
          { t: 'Titulaire', f: (p) => `<a href="#/utilisateurs/${p.id_utilisateur}">${esc(p.titulaire)}</a>${p.virement_auto ? '<div class="small muted">virement automatique</div>' : ''}` },
          { t: 'Solde', cl: 'r', f: (p) => `<b class="num">${fcfa(p.solde_fcfa)}</b>` }], f.portefeuilles, { vide: 'Aucun portefeuille approvisionné.' })}</div>
      </div>`;
    barres($('#g1'), f.serie, 'encaisse_fcfa', fcfa, 160);
    barres($('#g2'), f.serie, 'commission_fcfa', fcfa, 160);
    barres($('#g3'), f.serie, 'verse_fcfa', fcfa, 160);
  }

  // Équipe ---------------------------------------------------------------------------------------------------
  async function pageEquipe(n) {
    vue(`<div class="page-head"><div><h1>Équipe MboaRide</h1><p>Qui peut ouvrir cette console, et avec quels droits.</p></div>
      <button class="btn" id="nommer">Ajouter un membre</button></div>
      <div class="grid cols-3" style="margin-bottom:16px">
        <div class="card flat"><h3>Super admin</h3><p class="small muted" style="margin:4px 0 0">Tout, y compris l'équipe.</p></div>
        <div class="card flat"><h3>Support</h3><p class="small muted" style="margin:4px 0 0">Utilisateurs, agréments, trajets.</p></div>
        <div class="card flat"><h3>Finance</h3><p class="small muted" style="margin:4px 0 0">Paiements, remboursements, finances.</p></div>
      </div>
      <div class="card" id="resultats">${squelette(1, 160)}</div>`);
    const liste = await api('/api/admin/administrateurs');
    if (!actuel(n)) return;
    $('#resultats').innerHTML = tableau([
      { t: 'Membre', f: (a) => personne(`${a.prenom} ${a.nom}`, esc(a.email || a.telephone)) },
      { t: 'Rôle', f: (a) => (a.actif ? pastille('role', a.role) : '<span class="pill">Retiré</span>') },
      { t: 'Depuis', f: (a) => `${jour(a.cree_le)}${a.cree_par ? `<div class="small muted">par ${esc(a.cree_par)}</div>` : ''}` },
      { t: '', cl: 'r', f: (a) => (a.actif && a.id_utilisateur !== moi.id_utilisateur ? `<button class="btn ghost sm" data-retirer="${a.id_utilisateur}">Retirer</button>` : '') },
    ], liste);
    $$('[data-retirer]').forEach((b) => {
      b.onclick = async () => {
        const a = liste.find((x) => x.id_utilisateur === Number(b.dataset.retirer));
        const ok = await demander({ titre: `Retirer ${a.prenom} ${a.nom} de l'équipe ?`, texte: "La personne garde son compte dans l'application.", bouton: 'Retirer', danger: true,
          action: () => api(`/api/admin/administrateurs/${a.id_utilisateur}`, { methode: 'DELETE' }) });
        if (ok) { toast('Droits retirés.'); router(); }
      };
    });
    $('#nommer').onclick = async () => {
      const ok = await demander({
        titre: 'Ajouter un membre', texte: "La personne doit déjà avoir un compte dans l'application. Elle se connectera avec ses identifiants habituels.", bouton: 'Ajouter',
        champs: [{ nom: 'identifiant', label: 'E-mail ou téléphone', requis: true },
          { nom: 'role', label: 'Rôle', type: 'select', valeur: 'support', options: [['support', 'Support'], ['finance', 'Finance'], ['super_admin', 'Super admin']] }],
        action: (v) => api('/api/admin/administrateurs', { methode: 'POST', corps: v }),
      });
      if (ok) { toast(`${ok.prenom} ${ok.nom} rejoint l'équipe.`); router(); }
    };
  }

  // Journal -------------------------------------------------------------------------------------------------
  async function pageJournal(n) {
    const etat = E.journal ||= { page: 1 };
    vue(`<div class="page-head"><div><h1>Journal d'audit</h1><p>Chaque action de l'équipe, avec son auteur et son motif.</p></div></div>
      <div class="card" id="resultats">${squelette(1, 240)}</div>`);
    const charger = async () => {
      const m = ++rendu;
      const res = await api(`/api/admin/journal?${qs({ page: etat.page })}`);
      if (!actuel(m)) return;
      const el = $('#resultats');
      el.innerHTML = tableau([
        { t: 'Quand', f: (j) => `<span class="num">${quand(j.cree_le)}</span>` },
        { t: 'Par', f: (j) => esc(j.par || 'ligne de commande') },
        { t: 'Action', f: (j) => `<span class="pill plain">${esc(j.action.replace(/_/g, ' '))}</span>` },
        { t: 'Détail', f: (j) => (j.cible_type === 'utilisateur' && j.cible_id ? `<a href="#/utilisateurs/${esc(j.cible_id)}">${esc(j.resume)}</a>`
          : j.cible_type === 'trajet' ? `<a href="#/trajets/${esc(j.cible_id)}">${esc(j.resume)}</a>` : esc(j.resume)) },
      ], res.lignes, { vide: 'Aucune action enregistrée pour le moment.' }) + pager(res);
      brancherPager(el, etat, charger);
    };
    await charger();
  }

  const PAGES = {
    tableau: pageTableau, utilisateurs: pageUtilisateurs, agrements: pageAgrements, trajets: pageTrajets,
    paiements: pagePaiements, finances: pageFinances, equipe: pageEquipe, journal: pageJournal,
  };

  if (session) demarrer(); else pageConnexion();
})();
