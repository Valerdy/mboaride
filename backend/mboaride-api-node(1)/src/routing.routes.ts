import { Router } from "express";
import type { Knex } from "knex";
import { z } from "zod";
import { config } from "./config.js";
import { HttpError } from "./errors.js";
import { requireAuth } from "./middleware.js";
import type { OsrmClient } from "./osrm.js";
import { computeDetour, mapLimit } from "./routing.js";

const a = config.serviceArea;
const latLng = z
  .object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) })
  .refine((p) => p.lat >= a.minLat && p.lat <= a.maxLat && p.lng >= a.minLng && p.lng <= a.maxLng, {
    message: "Point hors de la zone de service (Douala et environs)",
  });
const trip = z.object({ origin: latLng, destination: latLng });

const routeSchema = z.object({ from: latLng, to: latLng, include_geometry: z.boolean().default(true) });
const detourSchema = z.object({
  driver: trip, pickup: latLng, dropoff: latLng, max_detour_s: z.number().int().nonnegative().optional(),
});
const detoursSchema = z.object({
  pickup: latLng, dropoff: latLng,
  drivers: z.array(trip.extend({ id: z.union([z.string(), z.number()]), max_detour_s: z.number().int().nonnegative().optional() })).min(1).max(50),
});

export function routingRouter(db: Knex, osrm: OsrmClient): Router {
  const router = Router();

  /** État du service d'itinéraires (route test dans Douala). Sans authentification. */
  router.get("/status", async (_req, res) => {
    try {
      const r = await osrm.route([{ lat: 4.0511, lng: 9.7679 }, { lat: 4.0435, lng: 9.7062 }]);
      res.json({ osrm: "ok", sample_duration_s: r.duration_s });
    } catch {
      res.status(503).json({ osrm: "unavailable" });
    }
  });

  router.use(requireAuth(db));

  /** Itinéraire entre deux points : distance, durée, tracé GeoJSON pour la carte Leaflet (US08). */
  router.post("/route", async (req, res) => {
    const d = routeSchema.parse(req.body);
    const r = await osrm.route([d.from, d.to], { geometry: d.include_geometry });
    res.json({ distance_m: r.distance_m, duration_s: r.duration_s, geometry: r.geometry ?? null });
  });

  /** Détour d'un conducteur pour un passager (agent conducteur, US03/US05). */
  router.post("/detour", async (req, res) => {
    const d = detourSchema.parse(req.body);
    res.json(await computeDetour(osrm, d.driver, d.pickup, d.dropoff, d.max_detour_s));
  });

  /** Compare plusieurs conducteurs pour un même passager, du plus petit détour au plus grand (agent coordinateur). */
  router.post("/detours", async (req, res) => {
    const d = detoursSchema.parse(req.body);
    const results = await mapLimit(d.drivers, 5, async (drv) => {
      try {
        return { id: drv.id, ...(await computeDetour(osrm, drv, d.pickup, d.dropoff, drv.max_detour_s)) };
      } catch (e) {
        if (e instanceof HttpError) return { id: drv.id, error: e.message };
        throw e;
      }
    });
    const ok = results.filter((r): r is Extract<typeof r, { detour_s: number }> => "detour_s" in r);
    ok.sort((x, y) => x.detour_s - y.detour_s);
    res.json({ results: [...ok, ...results.filter((r) => "error" in r)] });
  });

  return router;
}
