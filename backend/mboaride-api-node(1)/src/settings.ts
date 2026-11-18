import type { Knex } from "knex";
import { config } from "./config.js";

/**
 * Réglages modifiables depuis la console d'administration (table `mboaride.parametre`,
 * partagée avec l'API Python). Sans schéma métier dans la base (tests, API Node lancée
 * seule), on garde la valeur de l'environnement.
 */
export async function otpMinutes(db: Knex): Promise<number> {
  try {
    const existe = await db.raw("SELECT to_regclass('mboaride.parametre') AS t");
    if (!existe.rows?.[0]?.t) return config.otpMinutes;
    const r = await db.raw("SELECT valeur FROM mboaride.parametre WHERE cle = 'otp_minutes'");
    const v = Number(r.rows?.[0]?.valeur);
    if (Number.isInteger(v) && v >= 1 && v <= 30) return v;
  } catch {
    /* base indisponible pour ce réglage : valeur par défaut */
  }
  return config.otpMinutes;
}
