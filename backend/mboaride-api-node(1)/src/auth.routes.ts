import { Request, Response, Router } from "express";
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

  /** Envoie un nouveau code (par e-mail par défaut, voir OTP_CHANNEL) et dit où il est parti. */
  async function issueOtp(user: UserRow): Promise<{ code: string; sentTo: string }> {
    await db("otp_codes").where({ user_id: user.id, consumed: false }).update({ consumed: true });
    const code = newOtp();
    await db("otp_codes").insert({
      user_id: user.id, code_hash: digest(code), expires_at: now() + config.otpMinutes * 60_000,
      attempts: 0, consumed: false,
    });
    const deliveries = await notifications.sendCode(
      { email: user.email, phone: user.phone, name: user.full_name }, code, config.otpMinutes);
    return { code, sentTo: notifications.describe(deliveries) };
  }

  const publicUser = (user: UserRow) => ({
    id: user.id, full_name: user.full_name, fullName: user.full_name, email: user.email, phone: user.phone,
  });

  /** Jetons de session. `token` et `user` servent l'application mobile, qui lit ces deux champs. */
  async function issueTokens(user: UserRow) {
    const raw = newRefreshToken();
    await db("refresh_tokens").insert({
      user_id: user.id, token_hash: digest(raw), revoked: false,
      expires_at: now() + config.refreshTokenDays * 86_400_000,
    });
    const access = createAccessToken(user.id);
    return {
      access_token: access, refresh_token: raw, token_type: "bearer",
      expires_in: config.accessTokenMinutes * 60, token: access, user: publicUser(user),
    };
  }

  /** Normalise un identifiant facultatif, ou lève une 422 explicite. */
  function normalized(raw: string | undefined, expected: "email" | "phone"): string | null {
    if (!raw) return null;
    try {
      const [kind, value] = normalizeIdentifier(raw);
      if (kind !== expected) throw new Error(expected === "email" ? "Email invalide" : "Numéro de téléphone invalide");
      return value;
    } catch (e) {
      throw new HttpError(422, (e as Error).message);
    }
  }

  router.post("/register", async (req, res) => {
    const data = registerSchema.parse(req.body);
    let kind: "email" | "phone", value: string;
    try {
      [kind, value] = normalizeIdentifier(data.identifier);
    } catch (e) {
      throw new HttpError(422, (e as Error).message);
    }
    const email = kind === "email" ? value : normalized(data.email, "email");
    const phone = kind === "phone" ? value : normalized(data.phone, "phone");

    // Un compte déjà vérifié avec cet e-mail ou ce téléphone bloque l'inscription.
    const matches = await db<UserRow>("users").where((q) => {
      if (email) q.orWhere({ email });
      if (phone) q.orWhere({ phone });
    });
    if (matches.some((u) => u.is_verified)) throw new HttpError(409, "Un compte existe déjà avec cet identifiant");
    if (matches.length > 1) {
      throw new HttpError(409, "Cet e-mail et ce téléphone appartiennent à deux comptes différents");
    }
    let user: UserRow | undefined = matches[0];

    const password_hash = await hashPassword(data.password);
    let company_id: number | null = null;
    if (email) { // rattachement automatique au cercle de l'entreprise (US01)
      const company = await db("companies").where({ email_domain: email.split("@")[1] }).first();
      company_id = company ? company.id : null;
    }
    if (!user) {
      const [row] = await db("users").insert({
        email, phone, full_name: data.full_name, password_hash, is_verified: false, company_id, created_at: now(),
      }).returning("id");
      user = (await db<UserRow>("users").where({ id: typeof row === "object" ? row.id : row }).first())!;
    } else {
      await db("users").where({ id: user.id }).update({ email, phone, full_name: data.full_name, password_hash, company_id });
      user = { ...user, email, phone };
    }
    const { code, sentTo } = await issueOtp(user);
    res.status(201).json({
      message: sentTo,
      identifier: phone ?? email, phone, email,
      // Démonstration locale seulement (EXPOSE_DEV_CODE=1) : l'application affiche le code.
      ...(config.exposeDevCode ? { devOtp: code } : {}),
    });
  });

  const verify = async (req: Request, res: Response) => {
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
    res.json(await issueTokens(user));
  };
  router.post("/verify", verify);
  router.post("/verify-otp", verify); // nom utilisé par l'application mobile

  const resend = async (req: Request, res: Response) => {
    const data = identifierSchema.parse(req.body);
    const user = await findUser(data.identifier);
    const sent = user && !user.is_verified ? await issueOtp(user) : null;
    // Réponse identique dans tous les cas : on ne révèle pas si le compte existe.
    res.json({
      message: "Si le compte existe, un nouveau code a été envoyé",
      ...(config.exposeDevCode && sent ? { devOtp: sent.code } : {}),
    });
  };
  router.post("/otp/resend", resend);
  router.post("/resend-otp", resend); // nom utilisé par l'application mobile

  router.post("/login", async (req, res) => {
    const data = loginSchema.parse(req.body);
    const user = await findUser(data.identifier);
    if (!user || !(await verifyPassword(user.password_hash, data.password))) {
      throw new HttpError(401, "Identifiants invalides");
    }
    if (!user.is_verified) throw new HttpError(403, "Compte non vérifié : saisissez le code reçu");
    res.json(await issueTokens(user));
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
    const user = await db<UserRow>("users").where({ id: token.user_id }).first();
    if (!user) throw new HttpError(401, "Session expirée, reconnectez-vous");
    res.json(await issueTokens(user));
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
      ...publicUser(user), is_verified: Boolean(user.is_verified), company: company ? company.name : null,
    });
  });

  return router;
}
