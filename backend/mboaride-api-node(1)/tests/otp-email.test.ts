import { afterEach, describe, expect, it } from "vitest";
import { describe as decrire, maskEmail, maskPhone, outbox, sendCode } from "../src/notifications.js";

const saved = { ...process.env };
afterEach(() => {
  process.env = { ...saved };
  outbox.length = 0;
});

describe("code de vérification par e-mail", () => {
  it("masque l'adresse et le numéro montrés à l'utilisateur", () => {
    expect(maskEmail("karl.ngapepoue@gmail.com")).toBe("ka***@gmail.com");
    expect(maskPhone("+237690112233")).toBe("+237 6** ** ** 33");
  });

  it("sans compte Gmail configuré, le code reste dans la console (démonstration)", async () => {
    delete process.env.SMTP_USER;
    delete process.env.SMTP_PASS;
    const deliveries = await sendCode({ email: "lina@exemple.cm", phone: "+237690000502" }, "123456");
    expect(deliveries).toEqual([{ channel: "console", to: "console du serveur" }]);
    expect(decrire(deliveries)).toContain("console du serveur");
    expect(outbox.at(-1)).toEqual(["+237690000502", "123456"]);
  });

  it("annonce l'e-mail ou le SMS d'où part le code", () => {
    expect(decrire([{ channel: "email", to: "li***@exemple.cm" }])).toBe("Code envoyé par e-mail à li***@exemple.cm");
    expect(decrire([{ channel: "email", to: "li***@exemple.cm" }, { channel: "sms", to: "+237 6** ** ** 02" }]))
      .toBe("Code envoyé par e-mail à li***@exemple.cm et par SMS au +237 6** ** ** 02");
  });
});
