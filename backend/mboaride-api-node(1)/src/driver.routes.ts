import { Router } from "express";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { Knex } from "knex";

export const DOC_TYPES = ["idCard", "license", "criminalRecord", "insurance"] as const;
const setDocSchema = z.object({ status: z.enum(["received", "missing"]) });

function parseDocs(raw: unknown): Record<string, string> {
    if (typeof raw === "string") {
        try { return JSON.parse(raw); } catch { return {}; }
    }
    return (raw as Record<string, string>) ?? {};
}

function view(row: any) {
    const docs = parseDocs(row.documents);
    const documents = Object.fromEntries(DOC_TYPES.map((t) => [t, docs[t] ?? "missing"]));
    const receivedCount = DOC_TYPES.filter((t) => documents[t] === "received").length;
    return { status: row.status, documents, receivedCount, total: DOC_TYPES.length };
}

async function getOrCreate(db: Knex, userId: string) {
    let row = await db("driver_agreements").where({ user_id: userId }).first();
    if (!row) {
        await db("driver_agreements").insert({ id: randomUUID(), user_id: userId, status: "pending", documents: "{}" });
        row = await db("driver_agreements").where({ user_id: userId }).first();
    }
    return row;
}

/** Réutilisable par les voyages interurbains : seul un conducteur agréé peut publier. */
export async function isAgreementActive(db: Knex, userId: string) {
    const row = await db("driver_agreements").where({ user_id: userId }).first();
    return row?.status === "active";
}

export function createDriverRouter(db: Knex, requireAuth: any) {
    const router = Router();

    const uid = (req: any): string | null => {
        const v = req.user?.sub ?? req.user?.id;
        return v ? String(v) : null;
    };

    // GET /routes/driver/agreement
    router.get("/driver/agreement", requireAuth, async (req: any, res, next) => {
        try {
            const userId = uid(req);
            if (!userId) return res.status(401).json({ detail: "Non authentifié" });
            return res.json(view(await getOrCreate(db, userId)));
        } catch (e) { next(e); }
    });

    // PUT /routes/driver/agreement/documents/:type  { status: "received" | "missing" }
    // (l'upload réel de fichier avec multer viendra ensuite)
    router.put("/driver/agreement/documents/:type", requireAuth, async (req: any, res, next) => {
        try {
            const userId = uid(req);
            if (!userId) return res.status(401).json({ detail: "Non authentifié" });
            const type = req.params.type;
            if (!(DOC_TYPES as readonly string[]).includes(type)) {
                return res.status(400).json({ detail: "Type de document inconnu" });
            }
            const body = setDocSchema.safeParse(req.body);
            if (!body.success) return res.status(400).json({ detail: "Statut invalide" });

            const row = await getOrCreate(db, userId);
            if (row.status === "under_review" || row.status === "active") {
                return res.status(409).json({ detail: "Dossier déjà soumis, modification impossible." });
            }
            const docs = { ...parseDocs(row.documents), [type]: body.data.status };
            await db("driver_agreements")
                .where({ user_id: userId })
                .update({ documents: JSON.stringify(docs), updated_at: db.fn.now() });
            return res.json(view({ ...row, documents: docs }));
        } catch (e) { next(e); }
    });

    // POST /routes/driver/agreement/submit
    router.post("/driver/agreement/submit", requireAuth, async (req: any, res, next) => {
        try {
            const userId = uid(req);
            if (!userId) return res.status(401).json({ detail: "Non authentifié" });
            const row = await getOrCreate(db, userId);
            const v = view(row);
            if (v.receivedCount < v.total) {
                return res.status(400).json({ detail: `Il manque ${v.total - v.receivedCount} document(s).` });
            }
            if (row.status === "under_review" || row.status === "active") {
                return res.status(409).json({ detail: "Dossier déjà soumis." });
            }
            await db("driver_agreements")
                .where({ user_id: userId })
                .update({ status: "under_review", updated_at: db.fn.now() });
            return res.json({ ...v, status: "under_review" });
        } catch (e) { next(e); }
    });

    return router;
}