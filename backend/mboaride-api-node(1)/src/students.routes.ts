import { Router } from "express";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { Knex } from "knex";

const DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
const DEFAULT_PREFS = { onDeparture: true, onArrival: true, onDelay: true };

const prefsSchema = z.object({
    onDeparture: z.boolean(),
    onArrival: z.boolean(),
    onDelay: z.boolean(),
});

const routeSchema = z.object({
    pickupName: z.string().trim().min(2, "Indiquez le point de départ").max(120),
    dropoffName: z.string().trim().min(2, "Indiquez l’école").max(120),
    days: z.array(z.enum(DAYS)).min(1, "Choisissez au moins un jour").max(7),
    departTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Heure invalide (HH:mm)"),
});

const contactSchema = z.object({
    name: z.string().trim().min(2, "Nom de la personne de confiance requis").max(80),
    phone: z.string().trim().regex(/^\+?[0-9 ]{8,15}$/, "Numéro de téléphone invalide"),
});

const createSchema = z.object({
    firstName: z.string().trim().min(1, "Prénom requis").max(60, "Prénom trop long"),
    age: z
        .number()
        .int("Âge invalide")
        .min(12, "Le service est réservé aux élèves de 12 ans et plus")
        .max(25, "Âge invalide"),
    route: routeSchema,
    trustedContact: contactSchema,
    parentalConsent: z.boolean(),
});

const patchSchema = z.object({
    paused: z.boolean().optional(),
    authorized: z.boolean().optional(),
    alertPrefs: prefsSchema.optional(),
});

const idSchema = z.string().uuid();

function parseJson<T>(raw: unknown, fallback: T): T {
    if (typeof raw === "string") {
        try { return JSON.parse(raw) as T; } catch { return fallback; }
    }
    return (raw as T) ?? fallback;
}

function view(row: any, route?: any, contact?: any) {
    return {
        id: row.id,
        firstName: row.first_name,
        age: row.age,
        authorized: row.authorized,
        paused: row.paused ?? false,
        alertPrefs: { ...DEFAULT_PREFS, ...parseJson<Record<string, boolean>>(row.alert_prefs, {}) },
        route: route
            ? {
                pickupName: route.pickup_name,
                dropoffName: route.dropoff_name,
                days: parseJson<string[]>(route.days, []),
                departTime: route.depart_time,
            }
            : null,
        trustedContact: contact ? { name: contact.name, phone: contact.phone } : null,
    };
}

async function loadProfiles(db: Knex, where: Record<string, unknown>) {
    const rows = await db("student_accounts").where(where).orderBy("created_at", "asc");
    if (rows.length === 0) return [];
    const ids = rows.map((r: any) => r.id);
    const routes = await db("student_routes").whereIn("student_id", ids);
    const contacts = await db("trusted_contacts").whereIn("student_id", ids);
    const routeBy = new Map<string, any>(routes.map((r: any) => [r.student_id, r] as [string, any]));
    const contactBy = new Map<string, any>(contacts.map((c: any) => [c.student_id, c] as [string, any]));
    return rows.map((r: any) => view(r, routeBy.get(r.id), contactBy.get(r.id)));
}

async function removeStudent(db: Knex, id: string) {
    await db("student_routes").where({ student_id: id }).del();
    await db("trusted_contacts").where({ student_id: id }).del();
    await db("student_accounts").where({ id }).del();
}

export function createStudentsRouter(db: Knex, requireAuth: any) {
    const router = Router();

    const uid = (req: any): string | null => {
        const v = req.user?.sub ?? req.user?.id;
        return v ? String(v) : null;
    };
    const firstIssue = (e: z.ZodError) => e.issues[0]?.message ?? "Données invalides";

    // GET /routes/students
    router.get("/students", requireAuth, async (req: any, res, next) => {
        try {
            const userId = uid(req);
            if (!userId) return res.status(401).json({ detail: "Non authentifié" });
            return res.json({ students: await loadProfiles(db, { parent_user_id: userId }) });
        } catch (e) { next(e); }
    });

    // POST /routes/students  (profil complet : identité + trajet + personne de confiance)
    router.post("/students", requireAuth, async (req: any, res, next) => {
        try {
            const userId = uid(req);
            if (!userId) return res.status(401).json({ detail: "Non authentifié" });
            const parsed = createSchema.safeParse(req.body);
            if (!parsed.success) return res.status(400).json({ detail: firstIssue(parsed.error) });
            const d = parsed.data;
            if (!d.parentalConsent) {
                return res.status(400).json({ detail: "Le consentement parental est requis" });
            }

            const days = DAYS.filter((x) => d.route.days.includes(x));
            const id = randomUUID();
            try {
                await db("student_accounts").insert({
                    id,
                    parent_user_id: userId,
                    first_name: d.firstName,
                    age: d.age,
                    authorized: true,
                    paused: false,
                    school_route: `${d.route.pickupName} → ${d.route.dropoffName}`,
                    alert_prefs: JSON.stringify(DEFAULT_PREFS),
                });
                await db("student_routes").insert({
                    id: randomUUID(),
                    student_id: id,
                    pickup_name: d.route.pickupName,
                    dropoff_name: d.route.dropoffName,
                    days: JSON.stringify(days),
                    depart_time: d.route.departTime,
                });
                await db("trusted_contacts").insert({
                    id: randomUUID(),
                    student_id: id,
                    name: d.trustedContact.name,
                    phone: d.trustedContact.phone,
                });
            } catch (err) {
                try { await removeStudent(db, id); } catch { /* nettoyage au mieux */ }
                throw err;
            }

            const [profile] = await loadProfiles(db, { id });
            return res.status(201).json(profile);
        } catch (e) { next(e); }
    });

    // PATCH /routes/students/:id  { paused?, authorized?, alertPrefs? }
    router.patch("/students/:id", requireAuth, async (req: any, res, next) => {
        try {
            const userId = uid(req);
            if (!userId) return res.status(401).json({ detail: "Non authentifié" });
            if (!idSchema.safeParse(req.params.id).success) return res.status(404).json({ detail: "Enfant introuvable" });
            const parsed = patchSchema.safeParse(req.body);
            if (!parsed.success) return res.status(400).json({ detail: "Données invalides" });

            const d = parsed.data;
            const changes: Record<string, unknown> = {};
            if (d.paused !== undefined) changes.paused = d.paused;
            if (d.authorized !== undefined) changes.authorized = d.authorized;
            if (d.alertPrefs !== undefined) changes.alert_prefs = JSON.stringify(d.alertPrefs);
            if (Object.keys(changes).length === 0) return res.status(400).json({ detail: "Aucune modification" });

            const updated = await db("student_accounts")
                .where({ id: req.params.id, parent_user_id: userId })
                .update({ ...changes, updated_at: db.fn.now() });
            if (!updated) return res.status(404).json({ detail: "Enfant introuvable" });

            const [profile] = await loadProfiles(db, { id: req.params.id });
            return res.json(profile);
        } catch (e) { next(e); }
    });

    // DELETE /routes/students/:id
    router.delete("/students/:id", requireAuth, async (req: any, res, next) => {
        try {
            const userId = uid(req);
            if (!userId) return res.status(401).json({ detail: "Non authentifié" });
            if (!idSchema.safeParse(req.params.id).success) return res.status(404).json({ detail: "Enfant introuvable" });
            const owned = await db("student_accounts").where({ id: req.params.id, parent_user_id: userId }).first();
            if (!owned) return res.status(404).json({ detail: "Enfant introuvable" });
            await removeStudent(db, req.params.id);
            return res.status(204).end();
        } catch (e) { next(e); }
    });

    return router;
}