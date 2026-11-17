import crypto from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import type { Knex } from 'knex';

const agreementSchema = z.object({
    documents: z.object({
        idCard: z.boolean(),
        license: z.boolean(),
        criminalRecord: z.boolean(),
        insurance: z.boolean(),
    }),
    submitForReview: z.boolean().default(false),
});

const studentSchema = z.object({
    firstName: z.string().min(1),
    age: z.number().int().min(12).max(20),
    authorized: z.boolean().default(true),
    schoolRoute: z.string().min(3),
    alertPrefs: z.object({
        onDeparture: z.boolean(),
        onArrival: z.boolean(),
        onDelay: z.boolean(),
    }),
});

const intercityTripSchema = z.object({
    originCity: z.string().default('Douala'),
    destinationCity: z.string().default('Yaoundé'),
    dayLabel: z.string().min(1),
    departureTime: z.string().min(1),
    pickupPoints: z.array(z.string()).min(1),
    totalSeats: z.number().int().min(1).max(8).default(4),
    pricePerSeatFcfa: z.number().int().positive().default(3200),
    pickupOrder: z
        .array(
            z.object({
                rank: z.number().int(),
                passengerLabel: z.string(),
                point: z.string(),
                time: z.string(),
            })
        )
        .default([]),
});

export function createServicesRouter(db: Knex, requireAuth: any) {
    const router = Router();

    // --- ÉCRAN 1 : AGRÉMENT CONDUCTEUR ---
    router.get('/driver/agreement', requireAuth, async (req: any, res, next) => {
        try {
            const userId = req.user?.sub ?? req.user?.id;
            const agreement = await db('driver_agreements').where({ user_id: userId }).first();
            return res.json(
                agreement ?? {
                    status: 'pending',
                    documents: { idCard: true, license: true, criminalRecord: false, insurance: false },
                }
            );
        } catch (err) {
            next(err);
        }
    });

    router.post('/driver/agreement', requireAuth, async (req: any, res, next) => {
        try {
            const parsed = agreementSchema.safeParse(req.body);
            if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

            const userId = req.user?.sub ?? req.user?.id;
            const existing = await db('driver_agreements').where({ user_id: userId }).first();
            const nextStatus = parsed.data.submitForReview ? 'under_review' : 'pending';

            if (existing) {
                await db('driver_agreements')
                    .where({ user_id: userId })
                    .update({
                        documents: JSON.stringify(parsed.data.documents),
                        status: nextStatus,
                        updated_at: new Date(),
                    });
            } else {
                await db('driver_agreements').insert({
                    id: crypto.randomUUID(),
                    user_id: userId,
                    documents: JSON.stringify(parsed.data.documents),
                    status: nextStatus,
                });
            }

            const updated = await db('driver_agreements').where({ user_id: userId }).first();
            return res.status(200).json(updated);
        } catch (err) {
            next(err);
        }
    });

    // --- ÉCRAN 2 : COMPTES ÉLÈVES (US17, US19) ---
    router.get('/students', requireAuth, async (req: any, res, next) => {
        try {
            const parentId = req.user?.sub ?? req.user?.id;
            const students = await db('student_accounts')
                .where({ parent_user_id: parentId })
                .orderBy('created_at', 'asc');
            return res.json({ students });
        } catch (err) {
            next(err);
        }
    });

    router.post('/students', requireAuth, async (req: any, res, next) => {
        try {
            const parsed = studentSchema.safeParse(req.body);
            if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

            const parentId = req.user?.sub ?? req.user?.id;
            const id = crypto.randomUUID();
            await db('student_accounts').insert({
                id,
                parent_user_id: parentId,
                first_name: parsed.data.firstName,
                age: parsed.data.age,
                authorized: parsed.data.authorized,
                school_route: parsed.data.schoolRoute,
                alert_prefs: JSON.stringify(parsed.data.alertPrefs),
            });

            const created = await db('student_accounts').where({ id }).first();
            return res.status(201).json(created);
        } catch (err) {
            next(err);
        }
    });

    // --- ÉCRAN 3 : VOYAGE INTERURBAIN (US21, US22) ---
    router.get('/intercity/trips', requireAuth, async (_req, res, next) => {
        try {
            const trips = await db('intercity_trips').orderBy('created_at', 'desc');
            return res.json({ trips });
        } catch (err) {
            next(err);
        }
    });

    router.post('/intercity/trips', requireAuth, async (req: any, res, next) => {
        try {
            const parsed = intercityTripSchema.safeParse(req.body);
            if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

            const driverId = req.user?.sub ?? req.user?.id;
            const id = crypto.randomUUID();
            await db('intercity_trips').insert({
                id,
                driver_id: driverId,
                origin_city: parsed.data.originCity,
                destination_city: parsed.data.destinationCity,
                day_label: parsed.data.dayLabel,
                departure_time: parsed.data.departureTime,
                pickup_points: JSON.stringify(parsed.data.pickupPoints),
                total_seats: parsed.data.totalSeats,
                reserved_seats: parsed.data.pickupOrder.length,
                price_per_seat_fcfa: parsed.data.pricePerSeatFcfa,
                pickup_order: JSON.stringify(parsed.data.pickupOrder),
            });

            const created = await db('intercity_trips').where({ id }).first();
            return res.status(201).json(created);
        } catch (err) {
            next(err);
        }
    });

    return router;
}