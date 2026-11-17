import request from "supertest";
import type { Knex } from "knex";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.js";
import { config } from "../src/config.js";
import { createDb, migrate } from "../src/db.js";
import { outbox } from "../src/notifications.js";

// Contrat utilisé par l'application mobile (écran d'inscription de Cindy) :
// nom, e-mail et téléphone ensemble, `verify-otp`, et un champ `token` dans la réponse.
let db: Knex;
let api: ReturnType<typeof request>;
const BODY = { fullName: "Grâce Mbarga", email: "grace@entreprise-a.cm", phone: "690 11 22 33", password: "Motdepasse123" };

beforeAll(async () => {
  db = createDb("pglite:memory");
  await migrate(db);
  api = request(createApp(db, { rateLimit: false }));
});
afterAll(() => db.destroy());
beforeEach(async () => {
  await db.raw("TRUNCATE refresh_tokens, otp_codes, users, companies RESTART IDENTITY CASCADE");
  outbox.length = 0;
  (config as { exposeDevCode: boolean }).exposeDevCode = false;
});

describe("contrat de l'application mobile", () => {
  it("inscription avec e-mail et téléphone : le code part par SMS et le compte garde les deux", async () => {
    const r = await api.post("/auth/register").send(BODY);
    expect(r.status).toBe(201);
    expect(r.body).toMatchObject({ phone: "+237690112233", email: "grace@entreprise-a.cm" });
    expect(r.body.devOtp).toBeUndefined();
    expect(outbox.at(-1)![0]).toBe("+237690112233");

    const v = await api.post("/auth/verify-otp").send({ phone: "+237690112233", code: outbox.at(-1)![1] });
    expect(v.status).toBe(200);
    expect(v.body.token).toBe(v.body.access_token);
    expect(v.body.user).toMatchObject({ fullName: "Grâce Mbarga", email: "grace@entreprise-a.cm", phone: "+237690112233" });

    const login = await api.post("/auth/login").send({ identifier: "grace@entreprise-a.cm", password: BODY.password });
    expect(login.status).toBe(200);
    expect(login.body.token).toBeTruthy();
  });

  it("le code n'est renvoyé dans la réponse qu'en démonstration locale", async () => {
    (config as { exposeDevCode: boolean }).exposeDevCode = true;
    const r = await api.post("/auth/register").send(BODY);
    expect(r.body.devOtp).toBe(outbox.at(-1)![1]);
    const again = await api.post("/auth/resend-otp").send({ phone: BODY.phone });
    expect(again.body.devOtp).toBe(outbox.at(-1)![1]);
  });

  it("refuse un e-mail et un téléphone déjà pris par un compte vérifié", async () => {
    await api.post("/auth/register").send(BODY);
    await api.post("/auth/verify-otp").send({ phone: BODY.phone, code: outbox.at(-1)![1] });
    const r = await api.post("/auth/register").send({ ...BODY, phone: "699000000" });
    expect(r.status).toBe(409);
  });

  it("les routes protégées répondent 401 sans jeton au lieu de rester bloquées", async () => {
    const r = await api.get("/routes/crews").timeout(2000);
    expect(r.status).toBe(401);
  });
});
