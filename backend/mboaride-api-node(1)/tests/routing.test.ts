import http from "node:http";
import type { AddressInfo } from "node:net";
import request from "supertest";
import type { Knex } from "knex";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp } from "../src/app.js";
import { createDb, migrate } from "../src/db.js";
import { HttpError } from "../src/errors.js";
import { createOsrmClient, LatLng, OsrmClient, OsrmRoute, withCache } from "../src/osrm.js";
import { createAccessToken } from "../src/security.js";

// --- Faux OSRM : distance = vol d'oiseau x 1,3 ; vitesse 25 km/h -------------------------------
const rad = (d: number) => (d * Math.PI) / 180;
function dist(a: LatLng, b: LatLng): number {
  const dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(h)) * 1.3;
}
let calls = 0;
const fake: OsrmClient = {
  async route(points, opts = {}): Promise<OsrmRoute> {
    calls++;
    if (points.some((p) => p.lat > 4.24)) throw new HttpError(422, "Aucun itinéraire entre ces points");
    const legs = points.slice(1).map((p, i) => {
      const d = dist(points[i], p);
      return { distance_m: Math.round(d), duration_s: Math.round(d / 6.94) };
    });
    return {
      distance_m: legs.reduce((s, l) => s + l.distance_m, 0),
      duration_s: legs.reduce((s, l) => s + l.duration_s, 0),
      legs,
      geometry: opts.geometry ? { type: "LineString", coordinates: points.map((p) => [p.lng, p.lat]) } : undefined,
    };
  },
};

// Points de Douala (le long d'un même méridien pour des distances additives)
const LOGPOM = { lat: 4.0300, lng: 9.7400 };
const AKWA = { lat: 4.0500, lng: 9.7400 };
const BONANJO = { lat: 4.0700, lng: 9.7400 };
const BONAMOUSSADI = { lat: 4.0900, lng: 9.7400 };
const OFF_ROUTE = { lat: 4.0600, lng: 9.8000 };

let db: Knex;
let api: ReturnType<typeof request>;
let auth: string;

beforeAll(async () => {
  db = createDb("pglite:memory");
  await migrate(db);
  await db("users").insert({ email: "a@b.cm", full_name: "T", password_hash: "x", is_verified: true, created_at: Date.now() });
  auth = `Bearer ${createAccessToken(1)}`;
  api = request(createApp(db, { rateLimit: false, osrm: fake }));
});
afterAll(() => db.destroy());

const post = (url: string, body: unknown) => api.post(url).set("Authorization", auth).send(body);

describe("routes d'itinéraire", () => {
  it("calcule un itinéraire avec le tracé GeoJSON", async () => {
    const r = await post("/routes/route", { from: LOGPOM, to: BONANJO });
    expect(r.status).toBe(200);
    expect(r.body.distance_m).toBeGreaterThan(0);
    expect(r.body.geometry.type).toBe("LineString");
  });

  it("peut omettre le tracé", async () => {
    const r = await post("/routes/route", { from: LOGPOM, to: BONANJO, include_geometry: false });
    expect(r.body.geometry).toBeNull();
  });

  it("exige une session", async () => {
    expect((await api.post("/routes/route").send({ from: LOGPOM, to: BONANJO })).status).toBe(401);
  });

  it("refuse un point hors de la zone de service", async () => {
    const r = await post("/routes/route", { from: LOGPOM, to: { lat: 48.85, lng: 2.35 } });
    expect(r.status).toBe(422);
    expect(r.body.detail).toContain("zone de service");
  });

  it("refuse des coordonnées invalides", async () => {
    expect((await post("/routes/route", { from: { lat: "x", lng: 1 }, to: BONANJO })).status).toBe(422);
  });

  it("détour nul quand le passager est sur la route du conducteur", async () => {
    const r = await post("/routes/detour", { driver: { origin: LOGPOM, destination: BONAMOUSSADI }, pickup: AKWA, dropoff: BONANJO });
    expect(r.status).toBe(200);
    expect(r.body.detour_s).toBeLessThanOrEqual(2);
    expect(r.body.shared_distance_m).toBeGreaterThan(2000);
    expect(r.body.pickup_eta_s).toBeGreaterThan(0);
  });

  it("détour positif et limite respectée ou non", async () => {
    const body = { driver: { origin: LOGPOM, destination: BONAMOUSSADI }, pickup: OFF_ROUTE, dropoff: BONANJO };
    const ok = (await post("/routes/detour", { ...body, max_detour_s: 100000 })).body;
    const ko = (await post("/routes/detour", { ...body, max_detour_s: 60 })).body;
    expect(ok.detour_s).toBeGreaterThan(60);
    expect(ok.within_limit).toBe(true);
    expect(ko.within_limit).toBe(false);
    expect((await post("/routes/detour", body)).body.within_limit).toBeNull();
  });

  it("classe plusieurs conducteurs du plus petit détour au plus grand", async () => {
    const r = await post("/routes/detours", {
      pickup: AKWA, dropoff: BONANJO,
      drivers: [
        { id: "loin", origin: OFF_ROUTE, destination: BONAMOUSSADI },
        { id: "sur-la-route", origin: LOGPOM, destination: BONAMOUSSADI },
        { id: "impossible", origin: { lat: 4.245, lng: 9.7 }, destination: BONAMOUSSADI },
      ],
    });
    expect(r.status).toBe(200);
    expect(r.body.results.map((x: any) => x.id)).toEqual(["sur-la-route", "loin", "impossible"]);
    expect(r.body.results[2].error).toBeDefined();
  });

  it("l'état du service répond sans authentification", async () => {
    const r = await api.get("/routes/status");
    expect(r.status).toBe(200);
    expect(r.body.osrm).toBe("ok");
  });
});

describe("client OSRM HTTP", () => {
  let server: http.Server, base: string;
  const urls: string[] = [];
  beforeAll(async () => {
    server = http.createServer((req, res) => {
      urls.push(req.url!);
      res.setHeader("Content-Type", "application/json");
      if (req.url!.includes("9.9,4.2")) return void res.end(JSON.stringify({ code: "NoRoute" }));
      if (req.url!.includes("9.8,4.1")) return void res.end(JSON.stringify({ code: "NoSegment" }));
      res.end(JSON.stringify({
        code: "Ok",
        routes: [{ distance: 1234.6, duration: 98.4, geometry: { type: "LineString", coordinates: [[9.7, 4.0], [9.71, 4.01]] },
          legs: [{ distance: 600.2, duration: 50.1 }, { distance: 634.4, duration: 48.3 }] }],
      }));
    });
    await new Promise<void>((ok) => server.listen(0, ok));
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}/`;
  });
  afterAll(() => void server.close());

  it("envoie longitude,latitude et lit la réponse", async () => {
    const c = createOsrmClient(base, 1000);
    const r = await c.route([{ lat: 4.05, lng: 9.7 }, { lat: 4.04, lng: 9.71 }, { lat: 4.03, lng: 9.72 }], { geometry: true });
    expect(urls.at(-1)).toContain("/route/v1/driving/9.7,4.05;9.71,4.04;9.72,4.03");
    expect(urls.at(-1)).toContain("overview=full");
    expect(r).toMatchObject({ distance_m: 1235, duration_s: 98 });
    expect(r.legs).toHaveLength(2);
    expect(r.geometry?.coordinates).toHaveLength(2);
  });

  it("traduit les erreurs OSRM", async () => {
    const c = createOsrmClient(base, 1000);
    await expect(c.route([{ lat: 4.2, lng: 9.9 }, { lat: 4.0, lng: 9.7 }])).rejects.toMatchObject({ status: 422 });
    await expect(c.route([{ lat: 4.1, lng: 9.8 }, { lat: 4.0, lng: 9.7 }])).rejects.toMatchObject({ status: 422 });
  });

  it("répond 503 si OSRM est injoignable", async () => {
    const c = createOsrmClient("http://127.0.0.1:1", 500);
    await expect(c.route([LOGPOM, BONANJO])).rejects.toMatchObject({ status: 503 });
  });

  it("le cache évite de rappeler OSRM", async () => {
    let n = 0;
    const cached = withCache({ route: async () => (n++, { distance_m: 1, duration_s: 1, legs: [] }) });
    await cached.route([LOGPOM, BONANJO]);
    await cached.route([LOGPOM, BONANJO]);
    await cached.route([LOGPOM, AKWA]);
    expect(n).toBe(2);
  });
});
