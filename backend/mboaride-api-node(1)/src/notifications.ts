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
export async function sendSmsOtp(phone: string, code: string): Promise<void> {
  const apiKey = process.env.SMS_API_KEY;
  const senderId = process.env.SMS_SENDER_ID || 'MboaRide';

  // Mode développement si aucune clé SMS n'est configurée dans .env
  if (!apiKey) {
    console.log(`\n📲 [SMS OTP -> ${phone}] Votre code de vérification MboaRide est : ${code}\n`);
    return;
  }

  // Exemple d'appel HTTP générique (ex: Africa's Talking / passerelle SMS)
  const response = await fetch(process.env.SMS_GATEWAY_URL || 'https://api.africastalking.com/version1/messaging', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'apiKey': apiKey,
      'Accept': 'application/json',
    },
    body: new URLSearchParams({
      username: process.env.SMS_USERNAME || 'sandbox',
      to: phone,
      message: `MboaRide : Votre code de confirmation est ${code}. Valable 10 minutes.`,
      from: senderId,
    }),
  });

  if (!response.ok) {
    const errText = await response.text();
    console.error('Erreur passerelle SMS:', errText);
    throw new Error("Impossible d'envoyer le SMS OTP");
  }
}