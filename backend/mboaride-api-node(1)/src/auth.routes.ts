import { Router } from 'express';
import { z } from 'zod';
import type { Knex } from 'knex';
import {
  createAccessToken,
  hashPassword,
  verifyPassword,
  newOtp,
  normalizeIdentifier,
} from './security.js';
import { requireAuth } from './middleware.js';
import { sendSmsOtp } from './notifications.js';

const pendingOtps = new Map<string, { code: string; expiresAt: number }>();
const TEN_MINUTES_MS = 10 * 60 * 1000;

const registerSchema = z.object({
  fullName: z.string().min(2, 'Le nom complet est requis'),
  email: z.string().email('Adresse email invalide'),
  phone: z.string().min(8, 'Numéro de téléphone invalide'),
  password: z.string().min(6, 'Le mot de passe doit contenir au moins 6 caractères'),
});

const verifyOtpSchema = z.object({
  phone: z.string().min(8),
  code: z.string().length(6, 'Le code OTP doit contenir 6 chiffres'),
});

const loginSchema = z.object({
  identifier: z.string().min(3, 'Email ou numéro de téléphone requis'),
  password: z.string().min(1, 'Mot de passe requis'),
});

export function authRouter(db: Knex) {
  const router = Router();

  // 1. INSCRIPTION + ENVOI DE L'OTP PAR SMS
  router.post('/register', async (req, res, next) => {
    try {
      const parsed = registerSchema.safeParse(req.body);
      if (!parsed.success) {
        return res.status(400).json({ error: parsed.error.issues[0]?.message ?? 'Données invalides' });
      }

      const fullName = parsed.data.fullName.trim();
      const [, email] = normalizeIdentifier(parsed.data.email);
      const [, phone] = normalizeIdentifier(parsed.data.phone);
      const passwordHash = await hashPassword(parsed.data.password);

      const existing = await db('users')
          .where({ email })
          .orWhere({ phone })
          .first();

      if (existing && existing.is_verified) {
        return res.status(409).json({ error: 'Un compte vérifié existe déjà avec cet email ou ce numéro.' });
      }

      // Dans router.post('/register', ...)
      if (existing) {
        await db('users').where({ id: existing.id }).update({
          full_name: fullName,
          email,
          phone,
          password_hash: passwordHash,
          updated_at: Date.now(),
        });
      } else {
        const now = Date.now();
        await db('users').insert({
          full_name: fullName,
          email,
          phone,
          password_hash: passwordHash,
          is_verified: false,
          created_at: now,
          updated_at: now,
        });
      }

      const otpCode = newOtp();
      pendingOtps.set(phone, {
        code: otpCode,
        expiresAt: Date.now() + TEN_MINUTES_MS,
      });

      await sendSmsOtp(phone, otpCode);

      return res.status(201).json({
        message: 'Code OTP envoyé par SMS',
        phone,
        ...(process.env.NODE_ENV !== 'production' ? { devOtp: otpCode } : {}),
      });
    } catch (err) {
      next(err);
    }
  });

  // 2. VÉRIFICATION DU CODE OTP SMS -> ACTIVATION & CONNEXION AUTO
  router.post('/verify-otp', async (req, res, next) => {
    try {
      const parsed = verifyOtpSchema.safeParse(req.body);
      if (!parsed.success) {
        return res.status(400).json({ error: 'Numéro ou code OTP invalide' });
      }

      const [, phone] = normalizeIdentifier(parsed.data.phone);
      const entry = pendingOtps.get(phone);

      if (!entry || entry.expiresAt < Date.now() || entry.code !== parsed.data.code) {
        return res.status(401).json({ error: 'Code OTP incorrect ou expiré.' });
      }

      pendingOtps.delete(phone);

      await db('users').where({ phone }).update({ is_verified: true, updated_at: new Date() });
      const user = await db('users').where({ phone }).first();

      if (!user) {
        return res.status(404).json({ error: 'Utilisateur introuvable' });
      }

      const token = createAccessToken(Number(user.id));

      return res.json({
        token,
        user: {
          id: user.id,
          fullName: user.full_name,
          email: user.email,
          phone: user.phone,
          role: user.role,
        },
      });
    } catch (err) {
      next(err);
    }
  });

  // 3. RENVOI DU CODE OTP PAR SMS
  router.post('/resend-otp', async (req, res, next) => {
    try {
      const rawPhone = String(req.body?.phone ?? '');
      if (rawPhone.length < 8) return res.status(400).json({ error: 'Numéro invalide' });

      const [, phone] = normalizeIdentifier(rawPhone);
      const otpCode = newOtp();
      pendingOtps.set(phone, {
        code: otpCode,
        expiresAt: Date.now() + TEN_MINUTES_MS,
      });

      await sendSmsOtp(phone, otpCode);
      return res.json({
        message: 'Nouveau code OTP envoyé par SMS',
        ...(process.env.NODE_ENV !== 'production' ? { devOtp: otpCode } : {}),
      });
    } catch (err) {
      next(err);
    }
  });

  // 4. CONNEXION PAR EMAIL OU TÉLÉPHONE + MOT DE PASSE
  router.post('/login', async (req, res, next) => {
    try {
      const parsed = loginSchema.safeParse(req.body);
      if (!parsed.success) {
        return res.status(400).json({ error: parsed.error.issues[0]?.message ?? 'Identifiants invalides' });
      }

      const [kind, normalized] = normalizeIdentifier(parsed.data.identifier);

      const user =
          kind === 'email'
              ? await db('users').where({ email: normalized }).first()
              : await db('users').where({ phone: normalized }).first();

      if (!user || !user.password_hash || !(await verifyPassword(user.password_hash, parsed.data.password))) {
        return res.status(401).json({ error: 'Email/téléphone ou mot de passe incorrect.' });
      }

      if (!user.is_verified) {
        const otpCode = newOtp();
        pendingOtps.set(user.phone, {
          code: otpCode,
          expiresAt: Date.now() + TEN_MINUTES_MS,
        });
        await sendSmsOtp(user.phone, otpCode);
        return res.status(403).json({
          error: 'Compte non vérifié. Un nouveau code SMS vient d’être envoyé.',
          requiresOtp: true,
          phone: user.phone,
        });
      }

      const token = createAccessToken(Number(user.id));

      return res.json({
        token,
        user: {
          id: user.id,
          fullName: user.full_name,
          email: user.email,
          phone: user.phone,
          role: user.role,
        },
      });
    } catch (err) {
      next(err);
    }
  });

  // 5. PROFIL UTILISATEUR
  router.get('/me', requireAuth, async (req: any, res, next) => {
    try {
      const userId = req.user?.sub ?? req.user?.id ?? req.userId;
      const user = await db('users').where({ id: userId }).first();
      if (!user) return res.status(404).json({ error: 'Utilisateur introuvable' });
      return res.json(user);
    } catch (err) {
      next(err);
    }
  });

  router.put('/profile', requireAuth, async (req: any, res, next) => {
    try {
      const userId = req.user?.sub ?? req.user?.id ?? req.userId;
      const { full_name, company, role } = req.body ?? {};
      await db('users')
          .where({ id: userId })
          .update({
            ...(full_name ? { full_name } : {}),
            ...(company !== undefined ? { company } : {}),
            ...(role ? { role } : {}),
            updated_at: new Date(),
          });
      const updated = await db('users').where({ id: userId }).first();
      return res.json(updated);
    } catch (err) {
      next(err);
    }
  });

  return router;
}