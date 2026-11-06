import { HttpError } from "./errors.js";

export interface LatLng { lat: number; lng: number }
export interface LineString { type: "LineString"; coordinates: [number, number][] }
export interface OsrmLeg { distance_m: number; duration_s: number }
export interface OsrmRoute { distance_m: number; duration_s: number; legs: OsrmLeg[]; geometry?: LineString }
export interface OsrmClient {
  route(points: LatLng[], opts?: { geometry?: boolean }): Promise<OsrmRoute>;
}

const UNAVAILABLE = "Service d'itinéraires indisponible";

/** Client HTTP du service `route` d'OSRM (profil voiture). */
export function createOsrmClient(baseUrl: string, timeoutMs: number, fetchFn: typeof fetch = fetch): OsrmClient {
  const base = baseUrl.replace(/\/+$/, "");
  return {
    async route(points, opts = {}) {
      const coords = points.map((p) => `${p.lng},${p.lat}`).join(";"); // OSRM attend longitude,latitude
      const url = `${base}/route/v1/driving/${coords}?overview=${opts.geometry ? "full" : "false"}&geometries=geojson&steps=false`;
      let res: Response;
      let body: any;
      try {
        res = await fetchFn(url, { signal: AbortSignal.timeout(timeoutMs) });
        body = await res.json();
      } catch {
        throw new HttpError(503, UNAVAILABLE);
      }
      if (body?.code === "NoRoute") throw new HttpError(422, "Aucun itinéraire entre ces points");
      if (body?.code === "NoSegment") throw new HttpError(422, "Un des points est trop éloigné d'une route");
      if (!res.ok || body?.code !== "Ok" || !body.routes?.length) throw new HttpError(503, UNAVAILABLE);
      const r = body.routes[0];
      return {
        distance_m: Math.round(r.distance),
        duration_s: Math.round(r.duration),
        legs: r.legs.map((l: any) => ({ distance_m: Math.round(l.distance), duration_s: Math.round(l.duration) })),
        geometry: opts.geometry ? r.geometry : undefined,
      };
    },
  };
}

/** Cache mémoire : évite de recalculer les mêmes trajets (objectif de convergence < 2 s). */
export function withCache(client: OsrmClient, ttlMs = 10 * 60_000, max = 1000): OsrmClient {
  const store = new Map<string, { at: number; value: OsrmRoute }>();
  return {
    async route(points, opts = {}) {
      const key = points.map((p) => `${p.lat.toFixed(5)},${p.lng.toFixed(5)}`).join("|") + (opts.geometry ? "#g" : "");
      const hit = store.get(key);
      if (hit && Date.now() - hit.at < ttlMs) return hit.value;
      const value = await client.route(points, opts);
      if (store.size >= max) store.delete(store.keys().next().value as string);
      store.set(key, { at: Date.now(), value });
      return value;
    },
  };
}
