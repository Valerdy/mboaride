/* MboaRide · interface (US02, US09, US10, US13, US14, annulation, scénarios de démo). Sans dépendance. */
"use strict";

const $ = (s, el = document) => el.querySelector(s);
const fcfa = n => n == null ? "–" : `${Math.round(n).toLocaleString("fr-FR")} FCFA`;
const nombre = (n, d = 0) => n == null ? "–" : Number(n).toLocaleString("fr-FR", { maximumFractionDigits: d, minimumFractionDigits: d });
const pct = n => n == null ? "–" : `${nombre(n * 100, 0)} %`;
const dateCourte = s => s ? new Date(s).toLocaleDateString("fr-FR", { weekday: "short", day: "2-digit", month: "short" }) : "–";
const dateFr = s => s ? new Date(s).toLocaleDateString("fr-FR", { day: "2-digit", month: "short", year: "numeric" }) : "–";
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

const CERCLE = { organisation: "Collègue", partenaires: "Partenaire", public: "Public vérifié" };
const etat = { user: null, orgAdmin: null, offre: null, demandes: [], demandeVisee: null };

function stocker(k, v) { try { localStorage.setItem(k, v); } catch (_) { /* stockage indisponible */ } }
function lireStock(k) { try { return localStorage.getItem(k); } catch (_) { return null; } }

async function api(chemin, options = {}) {
  const rep = await fetch(chemin, {
    ...options,
    headers: { "Content-Type": "application/json", "X-Utilisateur": String(etat.user || ""), ...(options.headers || {}) },
  });
  const corps = rep.status === 204 ? null : await rep.json().catch(() => null);
  if (!rep.ok) {
    const d = corps && corps.detail;
    const err = new Error(typeof d === "string" ? d : (d && d.message) || (Array.isArray(d) ? d.map(x => x.msg).join(" · ") : `Erreur ${rep.status}`));
    err.status = rep.status; err.detail = d;
    throw err;
  }
  return corps;
}

function message(el, texte, type = "ok") { el.textContent = texte; el.className = `message ${type}`; }

/* ---------------------------------------------------------------- navigation */
function montrer(vue) {
  document.querySelectorAll(".vue").forEach(v => { v.hidden = v.id !== `vue-${vue}`; });
  document.querySelectorAll("#onglets button").forEach(b => b.setAttribute("aria-selected", String(b.dataset.vue === vue)));
  stocker("mboaride.vue", vue);
  if (vue === "exigences") chargerExigences();
  if (vue === "prix") chargerDemandes();
  if (vue === "console") chargerConsole();
  if (vue === "paiements") chargerPaiements();
  if (vue === "trajets") chargerTrajets();
  if (vue === "demo") chargerDemo();
  rafraichirBadge();
}
document.querySelectorAll("#onglets button").forEach(b => b.addEventListener("click", () => montrer(b.dataset.vue)));

async function initialiser() {
  const jeton = location.pathname.match(/^\/rejoindre\/([0-9a-f]{32})$/);
  await remplirComptes();
  if (jeton) { await vueRejoindre(jeton[1]); return; }
  await changerUtilisateur();
}

async function remplirComptes(forcer) {
  const users = await api("/api/demo/utilisateurs");
  const sel = $("#utilisateur");
  sel.innerHTML = users.map(u => `<option value="${u.id_utilisateur}">${esc(u.prenom)} ${esc(u.nom)}${u.administrateur ? " · admin RH" : ""}${u.demandes_ouvertes ? " · demande ouverte" : ""}</option>`).join("");
  const memo = lireStock("mboaride.user");
  sel.value = users.some(u => String(u.id_utilisateur) === memo) ? memo : String(users.find(u => u.prenom === "Grâce")?.id_utilisateur ?? users[0].id_utilisateur);
  if (forcer) await choisirCompte(forcer, false);
  etat.user = Number(sel.value);
}
$("#utilisateur").addEventListener("change", () => {
  stocker("mboaride.user", $("#utilisateur").value);
  if (location.pathname.startsWith("/rejoindre/")) { etat.user = Number($("#utilisateur").value); return; }
  changerUtilisateur();
});

/* Sélectionne un compte, en l'ajoutant à la liste s'il n'y figure pas (conducteur, nouvel inscrit). */
async function choisirCompte(uid, recharger = true) {
  const sel = $("#utilisateur");
  if (![...sel.options].some(o => Number(o.value) === uid)) {
    const u = await api(`/api/demo/utilisateur/${uid}`);
    sel.insertAdjacentHTML("beforeend", `<option value="${uid}">${esc(u.prenom)} ${esc(u.nom)}</option>`);
  }
  sel.value = String(uid); stocker("mboaride.user", sel.value);
  if (recharger) await changerUtilisateur(true);
}

async function changerUtilisateur(sansNavigation) {
  etat.user = Number($("#utilisateur").value);
  const [orgs, trajets] = await Promise.all([api("/api/moi/organisations"), api("/api/moi/trajets")]);
  const admin = orgs.find(o => o.role === "administrateur");
  etat.orgAdmin = admin || null;
  $('#onglets [data-vue="console"]').hidden = !admin;
  $('#onglets [data-vue="trajets"]').hidden = !trajets.length;
  $("#panneau-notifs").hidden = true;
  if (location.pathname.startsWith("/rejoindre/")) history.replaceState(null, "", "/");
  if (sansNavigation) return;
  let vue = lireStock("mboaride.vue") || "exigences";
  if ((vue === "console" && !admin) || (vue === "trajets" && !trajets.length)) vue = "exigences";
  montrer(vue);
}

/* ---------------------------------------------------------------- US02 */
const AIDE_CERCLE = {
  organisation: "Seulement des collègues de votre organisation.",
  partenaires: "Collègues, puis employés des entreprises partenaires si besoin.",
  public: "Collègues, partenaires, puis le réseau public de conducteurs agréés.",
};

async function chargerExigences() {
  const f = $("#form-exigences");
  message($("#msg-exigences"), "", "");
  const p = await api("/api/moi/preferences");
  f.climatisation.checked = p.confort.climatisation;
  f.non_fumeur.checked = p.confort.non_fumeur;
  f.silence.checked = p.confort.silence;
  f.prix_max_fcfa.value = p.prix_max_fcfa;
  f.querySelector(`[name=cercle][value=${p.cercle}]`).checked = true;
  f.querySelector(`[name=mode][value=${p.mode}]`).checked = true;
  f.querySelector(`[name=priorite][value=${p.priorite}]`).checked = true;
  $("#aide-cercle").textContent = AIDE_CERCLE[p.cercle];
  $("#moteur-params").textContent = JSON.stringify(p.parametres_moteur, null, 2);
}
$("#cercles").addEventListener("change", e => { $("#aide-cercle").textContent = AIDE_CERCLE[e.target.value]; });

$("#form-exigences").addEventListener("submit", async e => {
  e.preventDefault();
  const f = e.target;
  const corps = {
    confort: { climatisation: f.climatisation.checked, non_fumeur: f.non_fumeur.checked, silence: f.silence.checked },
    prix_max_fcfa: Number(f.prix_max_fcfa.value),
    cercle: f.querySelector("[name=cercle]:checked").value,
    mode: f.querySelector("[name=mode]:checked").value,
    priorite: f.querySelector("[name=priorite]:checked").value,
  };
  try {
    const p = await api("/api/moi/preferences", { method: "PUT", body: JSON.stringify(corps) });
    $("#moteur-params").textContent = JSON.stringify(p.parametres_moteur, null, 2);
    message($("#msg-exigences"), "Exigences enregistrées. Elles s'appliquent à vos prochaines demandes.");
  } catch (err) { message($("#msg-exigences"), err.message, "erreur"); }
});

/* ---------------------------------------------------------------- US09 */
async function chargerDemandes() {
  const sel = $("#demande");
  etat.demandes = await api("/api/moi/demandes");
  const ouvertes = etat.demandes.filter(d => d.statut === "ouverte");
  if (!ouvertes.length) {
    sel.innerHTML = "<option>Aucune demande ouverte</option>"; sel.disabled = true;
    $("#offres").innerHTML = `<p class="vide">Pas de demande en attente pour ce compte. Lancez un scénario depuis l'onglet Démo, ou choisissez Grâce Mbarga en haut de page.</p>`;
    $("#detail-prix").hidden = true; $("#diagnostic").hidden = true;
    return;
  }
  sel.disabled = false;
  sel.innerHTML = ouvertes.map(d => `<option value="${d.id_demande}">${esc(d.depart_libelle)} → ${esc(d.arrivee_libelle)}${d.date_unique ? ` · ${dateCourte(d.date_unique)}` : ""} · ${d.arrivee_au_plus_tot}–${d.arrivee_au_plus_tard} · max ${fcfa(d.prix_max_fcfa)}</option>`).join("");
  if (etat.demandeVisee && ouvertes.some(d => d.id_demande === etat.demandeVisee)) sel.value = String(etat.demandeVisee);
  etat.demandeVisee = null;
  chargerOffres();
}
$("#demande").addEventListener("change", chargerOffres);

async function chargerOffres() {
  const id = Number($("#demande").value);
  $("#detail-prix").hidden = true; $("#paiement-prix").hidden = true; message($("#msg-prix"), "", "");
  const offres = await api(`/api/moi/demandes/${id}/offres`);
  const box = $("#offres");
  if (!offres.some(o => o.confirmable)) await afficherDiagnostic(id); else $("#diagnostic").hidden = true;
  if (!offres.length) { box.innerHTML = ""; return; }
  box.innerHTML = offres.slice(0, 5).map((o, i) => `
    <button class="offre ${o.confirmable ? "" : "hors"}" data-i="${i}" aria-pressed="false">
      <span class="qui">${esc(o.conducteur)} · ${CERCLE[o.cercle]}</span>
      <span class="meta">${o.horaires_compatibles ? `Prise en charge ${o.prise_en_charge} · arrivée ${o.arrivee_estimee} · détour ${nombre(o.detour_km, 1)} km` : "Arrivée hors de votre fenêtre"}</span>
      <span class="prix">${fcfa(o.prix_fcfa)}</span>
    </button>`).join("");
  box.querySelectorAll(".offre").forEach(b => b.addEventListener("click", () => {
    box.querySelectorAll(".offre").forEach(x => x.setAttribute("aria-pressed", "false"));
    b.setAttribute("aria-pressed", "true");
    afficherPrix(offres[Number(b.dataset.i)]);
  }));
  afficherPrix(offres[0]);
  box.querySelector(".offre").setAttribute("aria-pressed", "true");
}

function prochaineDate(d) {
  if (d.date_unique) return d.date_unique;
  const j = new Date(); j.setDate(j.getDate() + 1);
  while (d.jours_semaine && d.jours_semaine[(j.getDay() + 6) % 7] !== "1") j.setDate(j.getDate() + 1);
  return j.toISOString().slice(0, 10);
}

function afficherPrix(o) {
  etat.offre = o;
  const d = etat.demandes.find(x => x.id_demande === o.id_demande);
  const box = $("#detail-prix");
  box.hidden = false;
  const alerte = !o.horaires_compatibles
    ? `<div class="bandeau rouge">Ce conducteur arriverait hors de votre fenêtre d'arrivée.</div>`
    : !o.dans_le_budget ? `<div class="bandeau rouge">Prix supérieur à votre maximum de ${fcfa(o.prix_max_fcfa)}.</div>`
    : `<div class="bandeau">Dans votre budget : ${fcfa(o.prix_max_fcfa - o.prix_fcfa)} sous votre maximum.</div>`;
  box.innerHTML = `
    <div class="recap">
      <h3>${esc(o.trajet)} · ${o.distance_km.toLocaleString("fr-FR")} km</h3>
      <ul class="lignes">${o.detail.map(l => `<li><span>${esc(l.libelle)}</span><span>${fcfa(l.montant_fcfa)}</span></li>`).join("")}</ul>
      <div class="total"><span>Vous payez</span><b>${fcfa(o.prix_fcfa)}</b></div>
      ${alerte}
      <label class="champ">Date du trajet <input type="date" id="date-trajet" value="${prochaineDate(d)}"></label>
      <button class="btn" id="btn-confirmer" ${o.confirmable ? "" : "disabled"}>Confirmer · ${fcfa(o.prix_fcfa)}</button>
      <p class="aide">Le prix affiché est celui qui sera payé par Mobile Money : s'il change avant la confirmation, vous êtes prévenu.</p>
    </div>`;
  $("#btn-confirmer").addEventListener("click", confirmer);
}

async function confirmer() {
  const o = etat.offre;
  try {
    const r = await api("/api/reservations", { method: "POST", body: JSON.stringify({
      id_demande: o.id_demande, id_trajet: o.id_trajet, date_trajet: $("#date-trajet").value, prix_annonce_fcfa: o.prix_fcfa }) });
    message($("#msg-prix"), `Trajet confirmé : prise en charge à ${r.prise_en_charge}, arrivée ${r.arrivee_estimee}. Il reste à payer ${fcfa(r.prix_fcfa)}.`);
    $("#btn-confirmer").disabled = true;
    $("#offres").innerHTML = ""; $("#detail-prix").hidden = true;
    const zone = $("#paiement-prix"); zone.hidden = false;
    formulairePaiement(zone, r.id_paiement, r.prix_fcfa, () => chargerDemandes());
  } catch (err) {
    if (err.status === 409 && err.detail && err.detail.nouveau_prix_fcfa) {
      message($("#msg-prix"), `${err.message} Nouveau prix : ${fcfa(err.detail.nouveau_prix_fcfa)}.`, "erreur");
      chargerOffres();
    } else message($("#msg-prix"), err.message, "erreur");
  }
}

/* ---------------------------------------------------------------- US13 + US14 */
function initPeriode() {
  const au = $("#au"), du = $("#du");
  if (!au.value) { const t = new Date(); au.value = t.toISOString().slice(0, 10); t.setMonth(t.getMonth() - 2, 1); du.value = t.toISOString().slice(0, 10); }
}
["#du", "#au"].forEach(s => $(s).addEventListener("change", chargerImpact));
$("#filtre-statut").addEventListener("change", chargerInvitations);

async function chargerConsole() {
  if (!etat.orgAdmin) return;
  $("#nom-org").textContent = etat.orgAdmin.nom;
  initPeriode();
  await Promise.all([chargerImpact(), chargerAdoption(), chargerInvitations()]);
}

function kpi(lib, val, note, classe = "") {
  return `<div class="kpi ${classe}"><div class="lib">${lib}</div><div class="val">${val}</div><div class="note">${note}</div></div>`;
}

async function chargerImpact() {
  const o = etat.orgAdmin.id_organisation;
  try {
    const r = await api(`/api/organisations/${o}/impact?du=${$("#du").value}&au=${$("#au").value}`);
    const ab = r.abonnement;
    $("#kpis-impact").innerHTML =
      kpi("Économies des employés", fcfa(r.economies_employes_fcfa), `face au taxi (${fcfa(r.hypotheses.reference_prix_ville_fcfa)} le trajet)`, "bon") +
      kpi("CO₂ évité", `${nombre(r.co2_evite_kg.prudent)} à ${nombre(r.co2_evite_kg.haut)} kg`, "fourchette prudente à haute") +
      kpi("Km de voiture évités", nombre(r.km_voiture_evites), `${nombre(r.litres_evites)} L d'essence non brûlés`) +
      kpi("Trajets partagés", nombre(r.trajets_partages), `prix moyen payé ${fcfa(r.prix_moyen_fcfa)}`) +
      kpi("Abonnement sur la période", fcfa(ab.cout_fcfa),
          ab.economies_par_fcfa_d_abonnement != null ? `${nombre(ab.economies_par_fcfa_d_abonnement, 2)} FCFA économisés par FCFA payé` : "abonnement inactif");
    const h = r.hypotheses;
    $("#hypotheses").innerHTML = [
      `Km évités : ${h.km_evites}.`,
      `Voiture que le passager aurait prise : ${nombre(h.conso_voiture_seule_l100, 1)} L/100 km ; ${nombre(h.co2_kg_par_litre, 2)} kg de CO₂ par litre.`,
      `Fourchette haute : ${h.scenario_haut} ; prudente : ${h.scenario_prudent}.`,
      `Économies : écart avec un taxi en ville (${fcfa(h.reference_prix_ville_fcfa)}) ou le car interurbain (${fcfa(h.reference_prix_interurbain_fcfa)}).`,
      `Abonnement : membres présents chaque mois × ${fcfa(ab.tarif_mensuel_fcfa)}.`,
    ].map(t => `<li>${esc(t)}</li>`).join("");
    $("#graphe-impact").innerHTML = barres(r.par_mois.map(m => ({ x: m.mois, a: m.trajets_partages, b: m.co2_evite_kg.prudent })),
      ["Trajets partagés", "CO₂ évité, prudent (kg)"]);
  } catch (err) { $("#kpis-impact").innerHTML = `<p class="message erreur">${esc(err.message)}</p>`; }
}

async function chargerAdoption() {
  const r = await api(`/api/organisations/${etat.orgAdmin.id_organisation}/adoption`);
  const inv = r.invitations;
  $("#kpis-adoption").innerHTML =
    kpi("Taux d'adoption", pct(r.taux_adoption), r.objectif_atteint ? `objectif de ${pct(r.objectif_adoption)} atteint`
        : `objectif ${pct(r.objectif_adoption)} · encore ${r.manque_pour_objectif} membres`, r.objectif_atteint ? "bon" : "alerte") +
    kpi("Membres inscrits", nombre(r.membres), `sur ${nombre(r.effectif)} employés · ${r.conducteurs_agrees} conducteurs agréés`) +
    kpi("Actifs sur 30 jours", nombre(r.membres_actifs_30j), `${pct(r.membres ? r.membres_actifs_30j / r.membres : null)} des membres`) +
    kpi("Invitations acceptées", pct(inv.taux_acceptation), `${inv.acceptees} sur ${inv.envoyees} · ${inv.en_attente} en attente · ${inv.expirees} expirées`);
  $("#graphe-adoption").innerHTML = barres(r.par_mois.map(m => ({ x: m.mois, a: m.membres_cumules, b: m.passagers_actifs })),
    ["Membres inscrits (cumul)", "Passagers actifs dans le mois"]);
  $("#table-services tbody").innerHTML = r.par_service.map(x => `<tr><td>${esc(x.service)}</td><td class="num">${x.membres}</td>
    <td class="num">${x.actifs_30j}</td><td class="num">${x.invitations_en_attente || ""}</td></tr>`).join("")
    || `<tr><td colspan="4" class="aide">Aucun membre.</td></tr>`;
}

async function chargerInvitations() {
  const st = $("#filtre-statut").value;
  const rows = await api(`/api/organisations/${etat.orgAdmin.id_organisation}/invitations${st ? `?statut=${st}` : ""}`);
  const lib = { envoyee: "En attente", acceptee: "Acceptée", expiree: "Expirée", annulee: "Annulée" };
  $("#table-invit tbody").innerHTML = rows.length ? rows.map(r => `
    <tr><td>${esc(r.email)}${r.membre ? `<div class="aide">${esc(r.membre)}</div>` : ""}</td><td>${esc(r.service || "–")}</td>
      <td><span class="statut ${r.statut}">${lib[r.statut]}</span></td>
      <td>${dateFr(r.envoyee_le)}${r.relances ? ` · ${r.relances} relance${r.relances > 1 ? "s" : ""}` : ""}</td>
      <td class="num">${r.statut === "acceptee" ? r.trajets : ""}</td>
      <td>${r.statut !== "acceptee" && r.relances < 3 ? `<button class="btn secondaire petit" data-id="${r.id_invitation}">Relancer</button>` : ""}</td></tr>`).join("")
    : `<tr><td colspan="6" class="aide">Aucune invitation.</td></tr>`;
  $("#table-invit tbody").querySelectorAll("button[data-id]").forEach(b => b.addEventListener("click", async () => {
    b.disabled = true;
    try { await api(`/api/organisations/${etat.orgAdmin.id_organisation}/invitations/${b.dataset.id}/relance`, { method: "POST" }); await Promise.all([chargerInvitations(), chargerAdoption()]); }
    catch (err) { b.textContent = err.message; }
  }));
}

$("#form-invit").addEventListener("submit", async e => {
  e.preventDefault();
  const emails = $("#emails").value.split(/[\n,]+/).map(x => x.trim()).filter(Boolean);
  const out = $("#resultat-invit");
  if (!emails.length) { out.innerHTML = `<p class="message erreur">Saisissez au moins une adresse.</p>`; return; }
  try {
    const r = await api(`/api/organisations/${etat.orgAdmin.id_organisation}/invitations`, { method: "POST", body: JSON.stringify({ emails, service: $("#service-defaut").value.trim() || null }) });
    out.innerHTML = `<div class="resultat">
      ${r.envoyees.length ? `<p class="message ok">${r.envoyees.length} invitation${r.envoyees.length > 1 ? "s" : ""} envoyée${r.envoyees.length > 1 ? "s" : ""}. ${esc(r.note)}</p>` : ""}
      ${r.envoyees.map(x => `<div>${esc(x.email)}${x.service ? ` · ${esc(x.service)}` : ""} · <a href="${esc(x.lien)}" target="_blank" rel="noopener">ouvrir le lien</a></div>`).join("")}
      ${r.ecartees.map(x => `<div class="message erreur">${esc(x.email)} : ${esc(x.motif)}</div>`).join("")}</div>`;
    $("#emails").value = "";
    await Promise.all([chargerInvitations(), chargerAdoption()]);
  } catch (err) { out.innerHTML = `<p class="message erreur">${esc(err.message)}</p>`; }
});

/* Barres groupées en SVG : deux séries, chacune sur sa propre échelle. */
function barres(points, noms) {
  if (!points.length) return `<p class="vide">Pas de données sur la période.</p>`;
  const L = 560, H = 210, g = 30, bas = H - 26, haut = 22;
  const maxA = Math.max(...points.map(p => p.a), 1), maxB = Math.max(...points.map(p => p.b), 1);
  const pas = (L - 2 * g) / points.length, larg = Math.min(34, pas / 3);
  const mois = m => new Date(`${m}-01`).toLocaleDateString("fr-FR", { month: "short", year: "2-digit" });
  const barresSvg = points.map((p, i) => {
    const cx = g + pas * (i + 0.5);
    const ha = (bas - haut) * p.a / maxA, hb = (bas - haut) * p.b / maxB;
    return `<rect x="${cx - larg - 2}" y="${bas - ha}" width="${larg}" height="${ha}" rx="4" fill="#0B6E4F"><title>${noms[0]} : ${nombre(p.a)}</title></rect>
      <rect x="${cx + 2}" y="${bas - hb}" width="${larg}" height="${hb}" rx="4" fill="#F2B705"><title>${noms[1]} : ${nombre(p.b)}</title></rect>
      <text x="${cx - larg / 2 - 2}" y="${bas - ha - 5}" text-anchor="middle">${nombre(p.a)}</text>
      <text x="${cx + larg / 2 + 2}" y="${bas - hb - 5}" text-anchor="middle">${nombre(p.b)}</text>
      <text x="${cx}" y="${H - 8}" text-anchor="middle">${mois(p.x)}</text>`;
  }).join("");
  return `<svg viewBox="0 0 ${L} ${H}" width="100%" role="img" aria-label="${noms.join(" et ")} par mois">
    <line x1="${g}" x2="${L - g}" y1="${bas}" y2="${bas}" stroke="#DCE3DE"/>${barresSvg}</svg>
    <div class="legende"><span><i style="background:#0B6E4F"></i>${noms[0]}</span><span><i style="background:#F2B705"></i>${noms[1]}</span></div>`;
}

/* ---------------------------------------------------------------- US14 export CSV */
$("#btn-csv").addEventListener("click", async () => {
  const b = $("#btn-csv");
  b.disabled = true;
  try {
    const rep = await fetch(`/api/organisations/${etat.orgAdmin.id_organisation}/impact.csv?du=${$("#du").value}&au=${$("#au").value}`,
      { headers: { "X-Utilisateur": String(etat.user) } });
    if (!rep.ok) throw new Error(`Erreur ${rep.status}`);
    const url = URL.createObjectURL(await rep.blob());
    const a = Object.assign(document.createElement("a"), { href: url, download: `mboaride_impact_${$("#du").value}_${$("#au").value}.csv` });
    document.body.append(a); a.click(); a.remove(); URL.revokeObjectURL(url);
  } catch (err) { b.textContent = err.message; }
  b.disabled = false;
});

/* ---------------------------------------------------------------- aucune offre et élargissement */
async function afficherDiagnostic(id) {
  const box = $("#diagnostic");
  const g = await api(`/api/moi/demandes/${id}/diagnostic`);
  box.hidden = false;
  box.innerHTML = `<div class="diagnostic">
    <h3>Aucune offre ne convient pour l'instant</h3>
    <p>${g.trajets_examines} trajet${g.trajets_examines > 1 ? "s" : ""} examiné${g.trajets_examines > 1 ? "s" : ""} par les agents :</p>
    <ul>${g.motifs.map(m => `<li><b>${m.trajets}</b> ${esc(m.libelle)}</li>`).join("")}</ul>
    ${g.suggestions.length ? `<p><b>Pour débloquer</b></p>` : `<p>Votre demande reste ouverte : vous serez prévenu dès qu'un conducteur compatible publie un trajet.</p>`}
    ${g.suggestions.map(x => x.action === "elargir"
      ? `<button class="btn" data-cercle="${x.cercle_max}">${esc(x.message)} · élargir</button>`
      : `<p class="aide">• ${esc(x.message)}</p>`).join("")}
  </div>`;
  box.querySelectorAll("[data-cercle]").forEach(b => b.addEventListener("click", async () => {
    b.disabled = true;
    try {
      const r = await api(`/api/moi/demandes/${id}/elargir`, { method: "POST", body: JSON.stringify({ cercle_max: b.dataset.cercle }) });
      etat.demandeVisee = id;
      await chargerDemandes();
      message($("#msg-prix"), `Cercle élargi : ${r.offres_ajoutees} offre${r.offres_ajoutees > 1 ? "s" : ""} en plus.`);
    } catch (err) { b.textContent = err.message; }
  }));
}

/* ---------------------------------------------------------------- US10 Mobile Money (simulé) */
const OPS = { mtn: "MTN Mobile Money", orange: "Orange Money" };

function formulairePaiement(zone, idPaiement, montant, apres) {
  zone.innerHTML = `<form class="paiement">
    <h3>Payer ${fcfa(montant)} par Mobile Money</h3>
    <div class="duo">
      <label class="bascule"><input type="radio" name="operateur" value="mtn" checked><span>MTN MoMo</span></label>
      <label class="bascule"><input type="radio" name="operateur" value="orange"><span>Orange Money</span></label>
    </div>
    <label class="champ">Numéro qui paie
      <span class="saisie">+237 <input name="telephone" inputmode="tel" placeholder="6 77 12 34 56" required></span>
    </label>
    <button class="btn" type="submit">Payer ${fcfa(montant)}</button>
    <p class="message" role="status"></p>
  </form>`;
  const f = $("form", zone), msg = $(".message", zone);
  f.addEventListener("submit", async e => {
    e.preventDefault();
    try {
      const r = await api(`/api/paiements/${idPaiement}/mobile-money`, { method: "POST",
        body: JSON.stringify({ operateur: f.querySelector("[name=operateur]:checked").value, telephone: f.telephone.value }) });
      telephoneSimule(zone, r, apres);
    } catch (err) { message(msg, err.message, "erreur"); }
  });
}

function telephoneSimule(zone, r, apres) {
  zone.innerHTML = `<div class="telephone">
    <div class="ecran">
      <div class="op">${esc(r.operateur)} · simulation</div>
      <p>${esc(r.message)}</p>
      <p class="ref">Réf. ${esc(r.reference)} · ${fcfa(r.montant_fcfa)}</p>
      <div class="pin" aria-hidden="true">• • • •</div>
    </div>
    <p class="aide">Simulation de ce que voit le payeur sur son téléphone :</p>
    <div class="actions">
      <button class="btn" data-r="valide">Valider avec mon code</button>
      <button class="btn secondaire" data-r="refuse">Refuser</button>
      <button class="btn secondaire" data-r="solde_insuffisant">Solde insuffisant</button>
      <button class="btn secondaire" data-r="delai_depasse">Ne pas répondre</button>
    </div>
  </div>`;
  zone.querySelectorAll("[data-r]").forEach(b => b.addEventListener("click", async () => {
    const p = await api(`/api/paiements/${r.id_paiement}/simulation-operateur`, { method: "POST", body: JSON.stringify({ resultat: b.dataset.r }) });
    if (p.statut === "reussi") { zone.innerHTML = recuHtml(p); if (apres) setTimeout(apres, 4000); rafraichirBadge(); }
    else {
      formulairePaiement(zone, p.id_paiement, p.montant_fcfa, apres);
      message($(".message", zone), p.tentatives_restantes > 0
        ? `Paiement échoué : ${p.motif_echec}. Encore ${p.tentatives_restantes} tentative${p.tentatives_restantes > 1 ? "s" : ""}.`
        : `Paiement échoué : ${p.motif_echec}. Nombre maximal de tentatives atteint.`, "erreur");
      if (p.tentatives_restantes <= 0) zone.querySelector("button[type=submit]").disabled = true;
    }
  }));
}

function recuHtml(p) {
  return `<div class="recu">
    <div class="tampon">Payé</div>
    <h3>Reçu · ${esc(p.reference)}</h3>
    <ul class="lignes">
      <li><span>Trajet</span><span>${esc(p.trajet)}, ${dateCourte(p.date_trajet)}</span></li>
      <li><span>Payé via</span><span>${esc(p.operateur)} · ${esc(p.telephone)}</span></li>
      <li><span>Reversé à ${esc(p.conducteur)} (frais partagés)</span><span>${fcfa(p.reverse_conducteur_fcfa)}</span></li>
      <li><span>Commission MboaRide</span><span>${fcfa(p.commission_fcfa)}</span></li>
    </ul>
    <div class="total"><span>Total payé</span><b>${fcfa(p.montant_fcfa)}</b></div>
  </div>`;
}

const STATUT_PAIEMENT = { en_attente: "À payer", reussi: "Payé", echoue: "Échoué", rembourse: "Remboursé" };

async function chargerPaiements() {
  const liste = await api("/api/moi/paiements");
  $("#paiement-zone").innerHTML = "";
  $("#liste-paiements").innerHTML = liste.length ? liste.map((p, i) => `
    <button class="offre" data-i="${i}">
      <span class="qui">${esc(p.trajet)}</span>
      <span class="meta">${dateCourte(p.date_trajet)} · avec ${esc(p.conducteur)}${p.reference ? ` · réf. ${esc(p.reference)}` : ""}${p.motif_echec ? ` · ${esc(p.motif_echec)}` : ""}</span>
      <span class="prix etat-${p.statut}">${STATUT_PAIEMENT[p.statut]} · ${fcfa(p.montant_fcfa)}</span>
    </button>`).join("") : `<p class="vide">Aucun paiement pour ce compte.</p>`;
  $("#liste-paiements").querySelectorAll(".offre").forEach(b => b.addEventListener("click", () => {
    const p = liste[Number(b.dataset.i)];
    const zone = $("#paiement-zone");
    if (p.statut === "reussi" || p.statut === "rembourse") zone.innerHTML = recuHtml(p).replace("Payé</div>", `${STATUT_PAIEMENT[p.statut]}</div>`);
    else if (p.tentatives_restantes > 0 && p.statut !== "rembourse") formulairePaiement(zone, p.id_paiement, p.montant_fcfa, chargerPaiements);
    else zone.innerHTML = `<p class="message erreur">Nombre maximal de tentatives atteint.</p>`;
    zone.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }));
}

/* ---------------------------------------------------------------- conducteur : annuler une date */
async function chargerTrajets() {
  const rows = (await api("/api/moi/trajets")).filter(r => r.date_trajet);
  $("#resultat-annulation").innerHTML = "";
  $("#liste-trajets").innerHTML = rows.length ? rows.map((r, i) => `
    <div class="offre statique">
      <span class="qui">${esc(r.depart_libelle)} → ${esc(r.arrivee_libelle)} · départ ${r.heure}</span>
      <span class="meta">${dateCourte(r.date_trajet)} · ${r.passagers} passager${r.passagers > 1 ? "s" : ""}</span>
      <button class="btn secondaire petit danger" data-i="${i}">Annuler ce jour</button>
    </div>`).join("") : `<p class="vide">Aucune réservation à venir sur vos trajets.</p>`;
  $("#liste-trajets").querySelectorAll("[data-i]").forEach(b => b.addEventListener("click", async () => {
    const r = rows[Number(b.dataset.i)];
    b.disabled = true;
    try {
      const a = await api(`/api/trajets/${r.id_trajet}/annulations`, { method: "POST",
        body: JSON.stringify({ date_trajet: r.date_trajet, motif: "empêchement du conducteur" }) });
      $("#resultat-annulation").innerHTML = `<div class="recap"><h3>Trajet du ${dateCourte(a.date_trajet)} annulé</h3>
        <ul class="lignes">${a.passagers.map(p => `<li><span>${esc(p.passager)} (mode ${esc(p.mode)})</span><span>${
          p.reaffecte ? `réaffecté à ${esc(p.nouveau_conducteur)}, ${fcfa(p.prix_fcfa)}`
          : p.offres_disponibles ? `${p.offres_disponibles} offre(s) proposée(s)` : "demande rouverte"}${
          p.paiement === "rembourse" ? " · remboursé" : ""}</span></li>`).join("")}</ul>
        <p class="aide">Chaque passager a été prévenu dans l'application.</p></div>`;
      b.closest(".offre").classList.add("annule");
    } catch (err) { b.textContent = err.message; }
  }));
}

/* ---------------------------------------------------------------- notifications */
const TYPE_NOTIF = { annulation: "Annulation", reaffectation: "Réaffectation", offres: "Offres", paiement: "Paiement",
  remboursement: "Remboursement", invitation: "Invitation" };
async function rafraichirBadge() {
  if (!etat.user) return;
  try {
    const n = (await api("/api/moi/notifications?marquer=false")).filter(x => !x.lue).length;
    $("#badge").hidden = !n; $("#badge").textContent = n;
  } catch (_) { /* compte sans notification */ }
}
$("#cloche").addEventListener("click", async () => {
  const p = $("#panneau-notifs");
  if (!p.hidden) { p.hidden = true; $("#cloche").setAttribute("aria-expanded", "false"); return; }
  const liste = await api("/api/moi/notifications");
  p.innerHTML = liste.length ? liste.map(n => `<div class="notif ${n.lue ? "" : "nouvelle"}"><span class="type">${esc(TYPE_NOTIF[n.type] || n.type)}</span>${esc(n.message)}<small>${new Date(n.cree_le).toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" })}</small></div>`).join("")
    : `<p class="aide">Aucune notification.</p>`;
  p.hidden = false; $("#cloche").setAttribute("aria-expanded", "true");
  $("#badge").hidden = true;
});

/* ---------------------------------------------------------------- SR-47 scénarios de démo */
const DESC_SCENARIO = {
  nominal: "Exigences, offres triées, prix détaillé, confirmation puis paiement Mobile Money.",
  annulation: "Le conducteur annule : remboursement, réaffectation automatique, notifications.",
  aucune_offre: "Aucun trajet compatible : l'appli explique pourquoi et propose quoi changer.",
  elargissement: "Rien entre collègues ; en élargissant au réseau public, une offre apparaît.",
};

async function chargerDemo() {
  const sc = await api("/api/demo/scenarios");
  $("#scenarios").innerHTML = sc.map((s, i) => `<div class="carte scenario"><span class="num-sc">${i + 1}</span>
    <h3>${esc(s.titre)}</h3><p>${esc(DESC_SCENARIO[s.code] || "")}</p>
    <button class="btn" data-code="${s.code}">Lancer</button></div>`).join("");
  $("#scenarios").querySelectorAll("[data-code]").forEach(b => b.addEventListener("click", () => lancerScenario(b.dataset.code, b)));
  chargerCourriels();
}

async function lancerScenario(code, bouton) {
  bouton.disabled = true;
  try {
    const s = await api(`/api/demo/scenarios/${code}`, { method: "POST" });
    $("#fil-titre").textContent = s.titre;
    $("#fil-etapes").innerHTML = s.etapes.map(e => `<li>${esc(e)}</li>`).join("");
    $("#fil").hidden = false;
    stocker("mboaride.fil", JSON.stringify({ titre: s.titre, etapes: s.etapes }));
    etat.demandeVisee = s.id_demande;
    await choisirCompte(s.utilisateur);
    montrer(s.onglet);
  } catch (err) { bouton.textContent = err.message; }
  bouton.disabled = false;
}
$("#fil-fermer").addEventListener("click", () => { $("#fil").hidden = true; stocker("mboaride.fil", ""); });
(() => { try { const f = JSON.parse(lireStock("mboaride.fil") || "null"); if (f) {
  $("#fil-titre").textContent = f.titre; $("#fil-etapes").innerHTML = f.etapes.map(e => `<li>${esc(e)}</li>`).join(""); $("#fil").hidden = false; } } catch (_) { /* rien */ } })();

async function chargerCourriels() {
  const c = await api("/api/demo/courriels");
  $("#courriels").innerHTML = c.length ? c.map(m => `<details><summary><span class="statut ${m.statut === "envoye" ? "acceptee" : m.statut === "echec" ? "expiree" : "envoyee"}">${m.statut === "simule" ? "simulé" : m.statut === "envoye" ? "envoyé" : "échec"}</span> ${esc(m.destinataire)} · ${esc(m.sujet)}</summary><pre>${esc(m.corps)}</pre></details>`).join("")
    : `<p class="aide">Aucun e-mail pour l'instant : envoyez une invitation depuis la console entreprise.</p>`;
}
$("#btn-courriels").addEventListener("click", chargerCourriels);

/* ---------------------------------------------------------------- lien d'invitation : rejoindre ou créer son compte */
async function vueRejoindre(jeton) {
  document.querySelectorAll(".vue").forEach(v => { v.hidden = v.id !== "vue-rejoindre"; });
  const corps = $("#corps-rejoindre");
  let inv;
  try { inv = await api(`/api/invitations/${jeton}`); }
  catch (err) { corps.innerHTML = `<p class="message erreur">${esc(err.message)}</p>`; return; }
  $("#sous-rejoindre").textContent = `${inv.organisation} vous invite${inv.service ? ` (service ${inv.service})` : ""}`;
  if (inv.compte_existant) {
    corps.innerHTML = `<p>Un compte existe déjà pour <b>${esc(inv.email)}</b>. Choisissez-le en haut de page, puis acceptez.</p>
      <button class="btn" id="btn-rejoindre">Accepter l'invitation</button><p class="message" id="msg-rejoindre" role="status"></p>`;
    $("#btn-rejoindre").addEventListener("click", async () => {
      try { const r = await api(`/api/invitations/${jeton}/accepter`, { method: "POST" }); message($("#msg-rejoindre"), r.message); }
      catch (err) { message($("#msg-rejoindre"), err.message, "erreur"); }
    });
    return;
  }
  corps.innerHTML = `<form id="form-inscription" class="corps sans-marge">
    <p>Créez votre compte pour rejoindre le cercle de covoiturage de <b>${esc(inv.organisation)}</b>.</p>
    <label class="champ">Adresse e-mail <input class="texte" value="${esc(inv.email)}" disabled></label>
    <label class="champ">Prénom <input class="texte" name="prenom" required maxlength="60"></label>
    <label class="champ">Nom <input class="texte" name="nom" required maxlength="60"></label>
    <label class="champ">Téléphone <span class="saisie">+237 <input name="telephone" inputmode="tel" placeholder="6 99 11 22 33" required></span></label>
    <label class="champ">Mot de passe (8 caractères au moins) <input class="texte" type="password" name="mot_de_passe" minlength="8" required></label>
    <button class="btn" type="submit">Créer mon compte et rejoindre</button>
    <p class="message" id="msg-rejoindre" role="status"></p></form>`;
  $("#form-inscription").addEventListener("submit", async e => {
    e.preventDefault();
    const f = e.target;
    try {
      const r = await api(`/api/invitations/${jeton}/inscription`, { method: "POST", body: JSON.stringify({
        prenom: f.prenom.value, nom: f.nom.value, telephone: f.telephone.value, mot_de_passe: f.mot_de_passe.value }) });
      message($("#msg-rejoindre"), `${r.message}. Vous allez être connecté.`);
      setTimeout(async () => { await choisirCompte(r.id_utilisateur, false); history.replaceState(null, "", "/"); await changerUtilisateur(); montrer("exigences"); }, 1500);
    } catch (err) { message($("#msg-rejoindre"), err.message, "erreur"); }
  });
}

initialiser().catch(err => { document.querySelector("main").insertAdjacentHTML("afterbegin", `<p class="message erreur">${esc(err.message)}</p>`); });
