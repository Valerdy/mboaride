import { Router } from 'express';
import { z } from 'zod';
import type { Knex } from 'knex';
import { AgentsEngine } from './agents.engine.js';
import { realtimeHub } from './realtime.js';

const createRideRequestSchema = z.object({
    pickup: z.object({
        name: z.string().min(1),
        lat: z.number().min(-90).max(90),
        lng: z.number().min(-180).max(180),
    }),
    dropoff: z.object({
        name: z.string().min(1),
        lat: z.number().min(-90).max(90),
        lng: z.number().min(-180).max(180),
    }),
    windowStart: z.string().datetime(),
    windowEnd: z.string().datetime(),
    maxPriceFcfa: z.number().int().positive(),
    comforts: z.array(z.string()).default([]),
});

export function createAgentsRouter(db: Knex, requireAuth: any) {
    const router = Router();
    const engine = new AgentsEngine(db);

    // 1. POST /routes/ride-requests — Soumettre une demande et déclencher le moteur d'agents
    router.post('/ride-requests', requireAuth, async (req: any, res, next) => {
        try {
            const parsed = createRideRequestSchema.safeParse(req.body);
            if (!parsed.success) {
                return res.status(400).json({ error: 'Données invalides', details: parsed.error.flatten() });
            }

            const userId = req.user?.sub ?? req.user?.id ?? 'anonymous';
            const result = await engine.processPassengerRequest({
                userId,
                ...parsed.data,
            });

            return res.status(201).json(result);
        } catch (err) {
            next(err);
        }
    });

    // 2. GET /routes/ride-requests/:id — Consulter l'état d'une demande et son équipage
    router.get('/ride-requests/:id', requireAuth, async (req, res, next) => {
        try {
            const request = await db('ride_requests').where({ id: req.params.id }).first();
            if (!request) return res.status(404).json({ error: 'Demande introuvable' });

            const crew = request.crew_id ? await engine.getCrewDetails(request.crew_id) : null;
            return res.json({ request, crew });
        } catch (err) {
            next(err);
        }
    });

    // 3. GET /routes/crews — Lister les équipages en cours de formation ou actifs
    router.get('/crews', requireAuth, async (_req, res, next) => {
        try {
            const crews = await db('crews').whereIn('status', ['forming', 'matched']).orderBy('created_at', 'desc');
            return res.json({ crews });
        } catch (err) {
            next(err);
        }
    });

    // 4. GET /routes/crews/:id — Détails complets d'un équipage et de ses membres
    router.get('/crews/:id', requireAuth, async (req, res, next) => {
        try {
            const details = await engine.getCrewDetails(req.params.id);
            if (!details) return res.status(404).json({ error: 'Équipage introuvable' });
            return res.json(details);
        } catch (err) {
            next(err);
        }
    });

    // 5. POST /routes/crews/:id/claim — Un conducteur prend en charge un équipage
    router.post('/crews/:id/claim', requireAuth, async (req: any, res, next) => {
        try {
            const driverId = req.user?.sub ?? req.user?.id;
            const updated = await engine.assignDriverToCrew(req.params.id, driverId);
            if (!updated) return res.status(404).json({ error: 'Équipage introuvable' });
            return res.json(updated);
        } catch (err) {
            next(err);
        }
    });

    // 6. GET /routes/realtime/stream — Flux temps réel (SSE) pour l'utilisateur connecté
    router.get('/realtime/stream', requireAuth, (req: any, res) => {
        const userId = req.user?.sub ?? req.user?.id ?? 'anonymous';

        res.setHeader('Content-Type', 'text/event-stream');
        res.setHeader('Cache-Control', 'no-cache');
        res.setHeader('Connection', 'keep-alive');
        res.flushHeaders?.();

        res.write(`event: connected\ndata: ${JSON.stringify({ userId, timestamp: new Date().toISOString() })}\n\n`);

        const heartbeat = setInterval(() => {
            res.write(': ping\n\n');
        }, 25000);

        const unsubscribe = realtimeHub.subscribeUser(userId, res);

        req.on('close', () => {
            clearInterval(heartbeat);
            unsubscribe();
        });
    });

    return router;
}