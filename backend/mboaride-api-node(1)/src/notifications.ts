import nodemailer from "nodemailer";
import twilio from "twilio";

/** Codes envoyés, gardés en mémoire : les tests y lisent le code, la démo l'affiche. */
export const outbox: Array<[string, string]> = [];

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || "smtp.gmail.com",
  port: Number(process.env.SMTP_PORT) || 587,
  secure: false,
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
});

const twilioClient =
  process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN
    ? twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN)
    : null;

/** Passerelle SMS HTTP (Africa's Talking ou compatible), si une clé est fournie dans .env. */
async function sendViaSmsGateway(phone: string, code: string): Promise<void> {
  const response = await fetch(process.env.SMS_GATEWAY_URL || "https://api.africastalking.com/version1/messaging", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      apiKey: process.env.SMS_API_KEY as string,
      Accept: "application/json",
    },
    body: new URLSearchParams({
      username: process.env.SMS_USERNAME || "sandbox",
      to: phone,
      message: `MboaRide : votre code de confirmation est ${code}.`,
      ...(process.env.SMS_SENDER_ID ? { from: process.env.SMS_SENDER_ID } : {}),
    }),
  });
  if (!response.ok) throw new Error(`Passerelle SMS : ${response.status} ${await response.text()}`);
}

/**
 * Envoie le code de vérification par e-mail ou par SMS selon l'identifiant.
 * Sans fournisseur configuré, le code s'affiche dans la console du serveur (développement).
 * Une panne du fournisseur ne bloque pas l'inscription : le code reste disponible en console.
 */
export async function sendCode(identifier: string, code: string): Promise<void> {
  outbox.push([identifier, code]);
  const isEmail = identifier.includes("@");
  try {
    if (isEmail && process.env.SMTP_USER) {
      await transporter.sendMail({
        from: '"MBOARIDE" <no-reply@mboaride.cm>',
        to: identifier,
        subject: "Votre code de vérification MBOARIDE",
        text: `Votre code est : ${code}`,
        html: `<h3>Bienvenue sur MBOARIDE</h3><p>Votre code est : <b>${code}</b></p>`,
      });
      console.log(`[E-mail] Code envoyé à ${identifier}`);
    } else if (!isEmail && process.env.SMS_API_KEY) {
      await sendViaSmsGateway(identifier, code);
      console.log(`[SMS] Code envoyé à ${identifier}`);
    } else if (!isEmail && twilioClient && process.env.TWILIO_PHONE_NUMBER) {
      await twilioClient.messages.create({
        body: `Votre code MBOARIDE est : ${code}`,
        from: process.env.TWILIO_PHONE_NUMBER,
        to: identifier,
      });
      console.log(`[SMS] Code envoyé à ${identifier}`);
    } else if (process.env.NODE_ENV !== "test") {
      console.log(`[Code de développement] ${identifier} : ${code}`);
    }
  } catch (err) {
    console.error("Envoi du code impossible :", err, `(code de ${identifier} : ${code})`);
  }
}
