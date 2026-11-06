import { z } from "zod";

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
