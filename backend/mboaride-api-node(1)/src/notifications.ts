import nodemailer from "nodemailer";
import twilio from "twilio";

/** Codes envoyés, gardés en mémoire : les tests y lisent le code, la démo l'affiche. */
export const outbox: Array<[string, string]> = [];

/** Destinataire d'un code : le compte a un e-mail, un téléphone, ou les deux. */
export interface Recipient {
  email?: string | null;
  phone?: string | null;
  name?: string | null;
}

/** Où le code est parti : canal et adresse masquée, à montrer à l'utilisateur. */
export interface Delivery {
  channel: "email" | "sms" | "console";
  to: string;
}

/**
 * Canal du code de vérification (variable OTP_CHANNEL) :
 *  - "email" (défaut) : par e-mail, via SMTP (Gmail avec un mot de passe d'application) ;
 *  - "sms" : par SMS (passerelle HTTP ou Twilio) ;
 *  - "email+sms" : les deux.
 * Sans fournisseur configuré pour le canal choisi, le code s'affiche dans la console du serveur.
 */
const otpChannel = () => (process.env.OTP_CHANNEL || "email").toLowerCase();
const smtpReady = () => Boolean(process.env.SMTP_USER && process.env.SMTP_PASS);
const smsReady = () =>
  Boolean(process.env.SMS_API_KEY ||
    (process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN && process.env.TWILIO_PHONE_NUMBER));

type Mailer = ReturnType<typeof nodemailer.createTransport>;
let transporter: Mailer | null = null;
function mailer(): Mailer {
  transporter ??= nodemailer.createTransport({
    host: process.env.SMTP_HOST || "smtp.gmail.com",
    port: Number(process.env.SMTP_PORT) || 587,
    secure: Number(process.env.SMTP_PORT) === 465,
    // Gmail affiche le mot de passe d'application en groupes de 4 : les espaces sont retirés.
    auth: { user: process.env.SMTP_USER, pass: (process.env.SMTP_PASS || "").replace(/\s+/g, "") },
  });
  return transporter;
}

/** « karl.ngapepoue@gmail.com » -> « ka***@gmail.com ». */
export function maskEmail(email: string): string {
  const [local, domain] = email.split("@");
  return `${local.slice(0, Math.min(2, local.length))}***@${domain}`;
}

/** « +237690112233 » -> « +237 6** ** ** 33 ». */
export function maskPhone(phone: string): string {
  const digits = phone.replace(/^\+237/, "");
  return digits.length === 9 ? `+237 ${digits[0]}** ** ** ${digits.slice(7)}` : `${phone.slice(0, 4)}…${phone.slice(-2)}`;
}

function emailHtml(code: string, name: string | null | undefined, minutes: number): string {
  const hello = name ? `Bonjour ${name.split(" ")[0]},` : "Bonjour,";
  return `<!doctype html>
<html lang="fr"><body style="margin:0;background:#f6f4ee;font-family:Arial,Helvetica,sans-serif;color:#12261f">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:24px 12px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
             style="max-width:480px;background:#ffffff;border-radius:16px;overflow:hidden">
        <tr><td style="background:#0b6e4f;padding:20px 24px;color:#ffffff;font-size:20px;font-weight:bold">
          MboaRide
        </td></tr>
        <tr><td style="padding:24px">
          <p style="margin:0 0 12px">${hello}</p>
          <p style="margin:0 0 20px">Voici votre code de vérification MboaRide :</p>
          <p style="margin:0 0 20px;text-align:center;font-size:34px;letter-spacing:10px;font-weight:bold;color:#0b6e4f">
            ${code}
          </p>
          <p style="margin:0 0 8px;color:#4a5751;font-size:14px">
            Il est valable ${minutes} minutes. Saisissez-le dans l'application pour activer votre compte.
          </p>
          <p style="margin:0;color:#4a5751;font-size:13px">
            Vous n'avez rien demandé ? Ignorez ce message : sans ce code, personne ne peut utiliser votre adresse.
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

async function sendEmail(to: string, code: string, name: string | null | undefined, minutes: number) {
  await mailer().sendMail({
    from: process.env.SMTP_FROM || `"MboaRide" <${process.env.SMTP_USER}>`,
    to,
    subject: `${code} est votre code MboaRide`,
    text: `Votre code de vérification MboaRide est ${code}. Il est valable ${minutes} minutes.`,
    html: emailHtml(code, name, minutes),
  });
}

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

async function sendSms(phone: string, code: string): Promise<void> {
  if (process.env.SMS_API_KEY) return sendViaSmsGateway(phone, code);
  const client = twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
  await client.messages.create({ body: `Votre code MboaRide est : ${code}`, from: process.env.TWILIO_PHONE_NUMBER, to: phone });
}

/**
 * Envoie le code de vérification par le canal choisi (OTP_CHANNEL) et renvoie où il est
 * parti. Une panne du fournisseur ne bloque pas l'inscription : le code reste dans la
 * console du serveur, et l'utilisateur peut en redemander un.
 */
export async function sendCode(recipient: Recipient, code: string, minutes = 5): Promise<Delivery[]> {
  outbox.push([(recipient.phone ?? recipient.email) as string, code]);
  const channel = otpChannel();
  const deliveries: Delivery[] = [];
  const byEmail = channel.includes("email") || !recipient.phone;
  const bySms = channel.includes("sms") || !recipient.email;

  if (byEmail && recipient.email && smtpReady()) {
    try {
      await sendEmail(recipient.email, code, recipient.name, minutes);
      deliveries.push({ channel: "email", to: maskEmail(recipient.email) });
      console.log(`[E-mail] Code envoyé à ${recipient.email}`);
    } catch (err) {
      console.error("Envoi du code par e-mail impossible :", (err as Error).message);
    }
  }
  if (bySms && recipient.phone && smsReady()) {
    try {
      await sendSms(recipient.phone, code);
      deliveries.push({ channel: "sms", to: maskPhone(recipient.phone) });
      console.log(`[SMS] Code envoyé à ${recipient.phone}`);
    } catch (err) {
      console.error("Envoi du code par SMS impossible :", (err as Error).message);
    }
  }
  if (!deliveries.length) {
    if (process.env.NODE_ENV !== "test") {
      console.log(`[Code de développement] ${recipient.email ?? recipient.phone} : ${code}`);
    }
    deliveries.push({ channel: "console", to: "console du serveur" });
  }
  return deliveries;
}

/** Message à montrer à l'utilisateur : « Code envoyé par e-mail à ka***@gmail.com ». */
export function describe(deliveries: Delivery[]): string {
  const sent = deliveries.filter((d) => d.channel !== "console");
  if (!sent.length) return "Code de vérification généré (aucun envoi configuré : voir la console du serveur)";
  return "Code envoyé " + sent.map((d) => (d.channel === "email" ? `par e-mail à ${d.to}` : `par SMS au ${d.to}`))
    .join(" et ");
}
