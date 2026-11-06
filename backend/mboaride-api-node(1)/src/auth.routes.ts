import { Router } from "express";
import { timingSafeEqual } from "node:crypto";
import type { Knex } from "knex";
import { config } from "./config.js";
import { HttpError } from "./errors.js";
import { AuthedRequest, requireAuth, UserRow } from "./middleware.js";
import * as notifications from "./notifications.js";
import { identifierSchema, loginSchema, refreshSchema, registerSchema, verifySchema } from "./schemas.js";
import {
  createAccessToken, digest, hashPassword, newOtp, newRefreshToken, normalizeIdentifier, verifyPassword,
} from "./security.js";

const now = () => Date.now();

export function authRouter(db: Knex): Router {
  const router = Router();

  async function findUser(identifier: string): Promise<UserRow | undefined> {
    try {
      const [kind, value] = normalizeIdentifier(identifier);
      return await db<UserRow>("users").where(kind === "email" ? { email: value } : { phone: value }).first();
    } catch {
      return undefined;
    }
  }

  async function issueOtp(user: UserRow): Promise<void> {
    await db("otp_codes").where({ user_id: user.id, consumed: false }).update({ consumed: true });
    const code = newOtp();
    await db("otp_codes").insert({
      user_id: user.id, code_hash: digest(code), expires_at: now() + config.otpMinutes * 60_000,
      attempts: 0, consumed: false,
    });
    notifications.sendCode((user.email ?? user.phone) as string, code);
  }

  async function issueTokens(userId: number) {
    const raw = newRefreshToken();
    await db("refresh_tokens").insert({
      user_id: userId, token_hash: digest(raw), revoked: false,
      expires_at: now() + config.refreshTokenDays * 86_400_000,
    });
    return {
      access_token: createAccessToken(userId), refresh_token: raw, token_type: "bearer",
      expires_in: config.accessTokenMinutes * 60,
    };
  }

  router.post("/register", async (req, res) => {
    const data = registerSchema.parse(req.body);
    let kind: "email" | "phone", value: string;
    try {
      [kind, value] = normalizeIdentifier(data.identifier);
    } catch (e) {
      throw new HttpError(422, (e as Error).message);
    }
    let user = await findUser(data.identifier);
    if (user?.is_verified) throw new HttpError(409, "Un compte existe déjà avec cet identifiant");

    const password_hash = await hashPassword(data.password);
    let company_id: number | null = null;
    if (kind === "email") { // rattachement automatique au cercle de l'entreprise (US01)
      const company = await db("companies").where({ email_domain: value.split("@")[1] }).first();
      company_id = company ? company.id : null;
    }
    if (!user) {
      const [row] = await db("users").insert({
        email: kind === "email" ? value : null, phone: kind === "phone" ? value : null,
        full_name: data.full_name, password_hash, is_verified: false, company_id, created_at: now(),
      }).returning("id");
      user = (await db<UserRow>("users").where({ id: typeof row === "object" ? row.id : row }).first())!;
    } else {
      await db("users").where({ id: user.id }).update({ full_name: data.full_name, password_hash, company_id });
    }
    await issueOtp(user);
    res.status(201).json({ message: "Code de vérification envoyé" });
  });

  router.post("/verify", async (req, res) => {
    const data = verifySchema.parse(req.body);
    const user = await findUser(data.identifier);
    const otp = user
      ? await db("otp_codes").where({ user_id: user.id, consumed: false }).orderBy("id", "desc").first()
      : undefined;
    if (!user || !otp || Number(otp.expires_at) < now()) throw new HttpError(400, "Code invalide ou expiré");
    if (otp.attempts >= config.otpMaxAttempts) throw new HttpError(429, "Trop de tentatives, demandez un nouveau code");
    const ok = timingSafeEqual(Buffer.from(otp.code_hash), Buffer.from(digest(data.code)));
    if (!ok) {
      await db("otp_codes").where({ id: otp.id }).increment("attempts", 1);
      throw new HttpError(400, "Code invalide ou expiré");
    }
    await db("otp_codes").where({ id: otp.id }).update({ consumed: true });
    await db("users").where({ id: user.id }).update({ is_verified: true });
    res.json(await issueTokens(user.id));
  });

  router.post("/otp/resend", async (req, res) => {
    const data = identifierSchema.parse(req.body);
    const user = await findUser(data.identifier);
    if (user && !user.is_verified) await issueOtp(user);
    // Réponse identique dans tous les cas : on ne révèle pas si le compte existe.
    res.json({ message: "Si le compte existe, un nouveau code a été envoyé" });
  });

  router.post("/login", async (req, res) => {
    const data = loginSchema.parse(req.body);
    const user = await findUser(data.identifier);
    if (!user || !(await verifyPassword(user.password_hash, data.password))) {
      throw new HttpError(401, "Identifiants invalides");
    }
    if (!user.is_verified) throw new HttpError(403, "Compte non vérifié : saisissez le code reçu");
    res.json(await issueTokens(user.id));
  });

  router.post("/refresh", async (req, res) => {
    const data = refreshSchema.parse(req.body);
    const token = await db("refresh_tokens").where({ token_hash: digest(data.refresh_token) }).first();
    if (!token || Number(token.expires_at) < now()) throw new HttpError(401, "Session expirée, reconnectez-vous");
    if (token.revoked) { // jeton déjà utilisé : on suspecte un vol et on coupe toutes les sessions
      await db("refresh_tokens").where({ user_id: token.user_id }).update({ revoked: true });
      throw new HttpError(401, "Session expirée, reconnectez-vous");
    }
    await db("refresh_tokens").where({ id: token.id }).update({ revoked: true }); // usage unique
    res.json(await issueTokens(token.user_id));
  });

  router.post("/logout", async (req, res) => {
    const data = refreshSchema.parse(req.body);
    await db("refresh_tokens").where({ token_hash: digest(data.refresh_token) }).update({ revoked: true });
    res.json({ message: "Déconnecté" });
  });

  router.get("/me", requireAuth(db), async (req, res) => {
    const user = (req as AuthedRequest).user;
    const company = user.company_id ? await db("companies").where({ id: user.company_id }).first() : null;
    res.json({
      id: user.id, email: user.email, phone: user.phone, full_name: user.full_name,
      is_verified: Boolean(user.is_verified), company: company ? company.name : null,
    });
  });

  return router;
}
