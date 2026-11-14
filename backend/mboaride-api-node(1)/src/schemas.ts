import { z } from "zod";
import { config } from "./config.js";

export const registerSchema = z.object({
  identifier: z.string().min(1, "Identifiant requis"),
  password: z.string().min(8, "Mot de passe trop court (8 caractères minimum)").max(128),
  full_name: z.string().min(2, "Nom trop court").max(120),
});
export const verifySchema = z.object({
  identifier: z.string().min(1),
  code: z.string().regex(/^\d{6}$/, "Le code contient 6 chiffres"),
});
export const identifierSchema = z.object({ identifier: z.string().min(1) });
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