import nodemailer from "nodemailer";
import twilio from "twilio";

// Tableau outbox conserve la compatibilité avec vos tests Vitest/Supertest
export const outbox: Array<[string, string]> = [];

// Transporter Nodemailer (Email)
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || "smtp.gmail.com",
  port: Number(process.env.SMTP_PORT) || 587,
  secure: false,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
});

// Client Twilio (SMS)
const twilioClient =
    process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN
        ? twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN)
        : null;

/**
 * Fonction appelée par auth.routes.ts lors de /register et /otp/resend
 */
export async function sendCode(identifier: string, code: string): Promise<void> {
  // 1. Alimente l'outbox en mémoire pour vos tests Vitest
  outbox.push([identifier, code]);

  const isEmail = identifier.includes("@");

  // 2. Envoi réel si les clés d'environnement sont configurées
  try {
    if (isEmail && process.env.SMTP_USER) {
      await transporter.sendMail({
        from: '"MBOARIDE" <no-reply@mboaride.cm>',
        to: identifier,
        subject: "Votre code de vérification MBOARIDE",
        text: `Votre code OTP est : ${code}`,
        html: `<h3>Bienvenue sur MBOARIDE</h3><p>Votre code OTP est : <b>${code}</b></p>`,
      });
      console.log(`[Email] Code envoyé à ${identifier}`);
    } else if (!isEmail && twilioClient && process.env.TWILIO_PHONE_NUMBER) {
      await twilioClient.messages.create({
        body: `Votre code MBOARIDE est : ${code}`,
        from: process.env.TWILIO_PHONE_NUMBER,
        to: identifier,
      });
      console.log(`[SMS] Code envoyé à ${identifier}`);
    } else {
      console.log(`[Outbox Dev] Code OTP généré pour ${identifier} : ${code}`);
    }
  } catch (err) {
    console.error("Erreur lors de l'envoi de la notification:", err);
  }
}