import { hash, verify } from "@node-rs/argon2";
import { createHmac, randomBytes, randomInt } from "node:crypto";
import jwt from "jsonwebtoken";
import { config } from "./config.js";
import { z } from 'zod';

export const hashPassword = (password: string) => hash(password); // Argon2id par défaut

export async function verifyPassword(passwordHash: string, password: string): Promise<boolean> {
  try {
    return await verify(passwordHash, password);
  } catch {
    return false;
  }
}
export const CreateRideRequestSchema = z.object({
  origin: z.string().nonempty("Le point de départ est requis"), // ou objets { lat, lng }
  destination: z.string().nonempty("La destination est requise"),
  windowStart: z.string().datetime(), // Ex: 2026-11-11T07:30:00Z
  windowEnd: z.string().datetime(),   // Ex: 2026-11-11T08:00:00Z
  maxPrice: z.number().positive(),    // Ex: 500
  currency: z.string().default("XAF"),
  preferences: z.object({
    airConditioning: z.boolean().default(false),
    silence: z.boolean().default(false),
  }).optional(),
}).refine(data => new Date(data.windowEnd) > new Date(data.windowStart), {
  message: "L'heure de fin doit être supérieure à l'heure de début",
  path: ["windowEnd"],
});
/** Empreinte HMAC : on ne stocke jamais un code ou un jeton en clair. */
export const digest = (value: string) => createHmac("sha256", config.secretKey).update(value).digest("hex");

export const newOtp = () => String(randomInt(0, 1_000_000)).padStart(6, "0");
export const newRefreshToken = () => randomBytes(48).toString("base64url");

export function createAccessToken(userId: number, seconds = config.accessTokenMinutes * 60): string {
  const exp = Math.floor(Date.now() / 1000) + seconds;
  return jwt.sign({ sub: String(userId), type: "access", exp }, config.secretKey, { algorithm: "HS256" });
}

export function decodeAccessToken(token: string): number | null {
  try {
    const data = jwt.verify(token, config.secretKey, { algorithms: ["HS256"] }) as jwt.JwtPayload;
    return data.type === "access" ? Number(data.sub) : null;
  } catch {
    return null;
  }
}

/** Retourne ["email", valeur] ou ["phone", "+237..."]. Lève une erreur si invalide. */
export function normalizeIdentifier(raw: string): ["email" | "phone", string] {
  const value = raw.trim();
  if (value.includes("@")) {
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value)) throw new Error("Email invalide");
    return ["email", value.toLowerCase()];
  }
  let digits = value.replace(/[\s\-.()]/g, "");
  if (digits.startsWith("00")) digits = "+" + digits.slice(2);
  if (!digits.startsWith("+")) digits = config.defaultCountryCode + digits.replace(/^0+/, "");
  if (!/^\+\d{8,15}$/.test(digits)) throw new Error("Numéro de téléphone invalide");
  return ["phone", digits];
}
