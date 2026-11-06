import request from "supertest";
import type { Knex } from "knex";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.js";
import { createDb, migrate } from "../src/db.js";
import { outbox } from "../src/notifications.js";
import { createAccessToken, normalizeIdentifier } from "../src/security.js";

const EMAIL = "cindy@entreprise.cm";
const PWD = "Motdepasse123";
let db: Knex;
let api: ReturnType<typeof request>;

beforeAll(async () => {
  db = createDb("pglite:memory"); // une seule base pour tous les tests (plus rapide)
  await migrate(db);
  api = request(createApp(db, { rateLimit: false }));
});
afterAll(() => db.destroy());
beforeEach(async () => {
  await db.raw("TRUNCATE refresh_tokens, otp_codes, users, companies RESTART IDENTITY CASCADE");
  outbox.length = 0;
});

const register = (identifier = EMAIL, password = PWD) =>
  api.post("/auth/register").send({ identifier, password, full_name: "Cindy T" });

async function registerAndVerify(identifier = EMAIL) {
  expect((await register(identifier)).status).toBe(201);
  const code = outbox.at(-1)![1];
  const r = await api.post("/auth/verify").send({ identifier, code });
  expect(r.status).toBe(200);
  return r.body;
}
const me = (token: string) => api.get("/auth/me").set("Authorization", `Bearer ${token}`);

describe("authentification", () => {
  it("parcours complet : inscription, code, profil", async () => {
    const t = await registerAndVerify();
    const r = await me(t.access_token);
    expect(r.status).toBe(200);
    expect(r.body.email).toBe(EMAIL);
  });

  it("le mot de passe est haché (Argon2)", async () => {
    await registerAndVerify();
    const u = await db("users").first();
    expect(u.password_hash).not.toContain(PWD);
    expect(u.password_hash.startsWith("$argon2")).toBe(true);
  });

  it("la connexion exige un compte vérifié", async () => {
    await register();
    expect((await api.post("/auth/login").send({ identifier: EMAIL, password: PWD })).status).toBe(403);
  });

  it("mauvais mot de passe et compte inconnu donnent la même erreur", async () => {
    await registerAndVerify();
    const a = await api.post("/auth/login").send({ identifier: EMAIL, password: "mauvais-mdp" });
    const b = await api.post("/auth/login").send({ identifier: "inconnu@x.cm", password: PWD });
    expect(a.status).toBe(401);
    expect(b.status).toBe(401);
    expect(a.body).toEqual(b.body);
  });

  it("refuse un mot de passe trop court", async () => {
    expect((await register(EMAIL, "court")).status).toBe(422);
  });

  it("refuse un doublon sur un compte vérifié", async () => {
    await registerAndVerify();
    expect((await register()).status).toBe(409);
  });

  it("bloque le code après 5 mauvaises tentatives", async () => {
    await register();
    const good = outbox.at(-1)![1];
    const bad = good === "000000" ? "111111" : "000000";
    for (let i = 0; i < 5; i++) {
      expect((await api.post("/auth/verify").send({ identifier: EMAIL, code: bad })).status).toBe(400);
    }
    expect((await api.post("/auth/verify").send({ identifier: EMAIL, code: good })).status).toBe(429);
  });

  it("refuse un code expiré", async () => {
    await register();
    const code = outbox.at(-1)![1];
    await db("otp_codes").update({ expires_at: 0 });
    expect((await api.post("/auth/verify").send({ identifier: EMAIL, code })).status).toBe(400);
  });

  it("un nouveau code invalide l'ancien", async () => {
    await register();
    const old = outbox.at(-1)![1];
    await api.post("/auth/otp/resend").send({ identifier: EMAIL });
    const fresh = outbox.at(-1)![1];
    if (old !== fresh) {
      expect((await api.post("/auth/verify").send({ identifier: EMAIL, code: old })).status).toBe(400);
    }
    expect((await api.post("/auth/verify").send({ identifier: EMAIL, code: fresh })).status).toBe(200);
  });

  it("rotation du jeton de rafraîchissement et détection de rejeu", async () => {
    const t1 = await registerAndVerify();
    const t2 = (await api.post("/auth/refresh").send({ refresh_token: t1.refresh_token })).body;
    expect(t2.refresh_token).not.toBe(t1.refresh_token);
    expect((await api.post("/auth/refresh").send({ refresh_token: t1.refresh_token })).status).toBe(401);
    expect((await api.post("/auth/refresh").send({ refresh_token: t2.refresh_token })).status).toBe(401);
  });

  it("la déconnexion révoque le jeton de rafraîchissement", async () => {
    const t = await registerAndVerify();
    expect((await api.post("/auth/logout").send({ refresh_token: t.refresh_token })).status).toBe(200);
    expect((await api.post("/auth/refresh").send({ refresh_token: t.refresh_token })).status).toBe(401);
  });

  it("refuse un jeton d'accès expiré", async () => {
    await registerAndVerify();
    expect((await me(createAccessToken(1, -60))).status).toBe(401);
  });

  it("refuse /me sans jeton", async () => {
    expect((await api.get("/auth/me")).status).toBe(401);
  });

  it("rattache l'utilisateur à son entreprise par le domaine de l'email", async () => {
    await db("companies").insert({ name: "Entreprise Test", email_domain: "entreprise.cm" });
    const t = await registerAndVerify();
    expect((await me(t.access_token)).body.company).toBe("Entreprise Test");
  });

  it("inscription par téléphone et normalisation du numéro", async () => {
    expect(normalizeIdentifier("6 77 12 34 56")).toEqual(["phone", "+237677123456"]);
    expect(normalizeIdentifier("+237 677 123 456")).toEqual(["phone", "+237677123456"]);
    const t = await registerAndVerify("677123456");
    expect((await me(t.access_token)).body.phone).toBe("+237677123456");
    expect(() => normalizeIdentifier("abc")).toThrow();
  });
});
