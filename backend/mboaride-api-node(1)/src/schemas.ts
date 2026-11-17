import { z } from "zod";
import { config } from "./config.js";

/**
 * Deux formes d'inscription sont acceptées :
 *  - `{ identifier, password, full_name }` : un seul identifiant, e-mail ou téléphone ;
 *  - `{ fullName, email, phone, password }` : formulaire de l'application mobile, qui
 *    demande les deux. Le code part alors par SMS, et l'e-mail sert au rattachement à
 *    l'entreprise et au rapprochement avec le profil métier de l'API Python.
 */
export const registerSchema = z.preprocess(
  (raw) => {
    const b = (raw ?? {}) as Record<string, unknown>;
    return {
      ...b,
      full_name: b.full_name ?? b.fullName,
      identifier: b.identifier ?? b.phone ?? b.email,
    };
  },
  z.object({
    identifier: z.string().min(1, "Identifiant requis"),
    password: z.string().min(8, "Mot de passe trop court (8 caractères minimum)").max(128),
    full_name: z.string().trim().min(2, "Nom trop court").max(120),
    email: z.string().trim().min(1).optional(),
    phone: z.string().trim().min(1).optional(),
  }),
);
/** `identifier` ou, pour l'application mobile, `phone` (ou `email`). */
const withIdentifier = (raw: unknown) => {
  const b = (raw ?? {}) as Record<string, unknown>;
  return { ...b, identifier: b.identifier ?? b.phone ?? b.email };
};
export const verifySchema = z.preprocess(withIdentifier, z.object({
  identifier: z.string().min(1, "Identifiant requis"),
  code: z.string().regex(/^\d{6}$/, "Le code contient 6 chiffres"),
}));
export const identifierSchema = z.preprocess(withIdentifier, z.object({ identifier: z.string().min(1, "Identifiant requis") }));
export const loginSchema = z.object({ identifier: z.string().min(1), password: z.string().min(1) });
export const refreshSchema = z.object({ refresh_token: z.string().min(1) });
const a = config.serviceArea;

const latLngSchema = z
    .object({
      lat: z.number().min(-90).max(90),
      lng: z.number().min(-180).max(180),
    })
    .refine((p) => p.lat >= a.minLat && p.lat <= a.maxLat && p.lng >= a.minLng && p.lng <= a.maxLng, {
      message: "Point hors de la zone de service (Douala et environs)",
    });

export const CreateRideRequestSchema = z.object({
  origin: z.union([z.string().min(1), latLngSchema]),
  destination: z.union([z.string().min(1), latLngSchema]),
  windowStart: z.string().datetime({ message: "Format ISO datetime requis pour windowStart" }),
  windowEnd: z.string().datetime({ message: "Format ISO datetime requis pour windowEnd" }),
  maxPrice: z.number().positive("Le prix maximal doit être supérieur à 0"),
  currency: z.string().default("XAF"),
  preferences: z.object({
    airConditioning: z.boolean().default(false),
    silence: z.boolean().default(false),
  }).optional(),
}).refine((data) => new Date(data.windowEnd) > new Date(data.windowStart), {
  message: "L'heure de fin doit être supérieure à l'heure de début",
  path: ["windowEnd"],
});