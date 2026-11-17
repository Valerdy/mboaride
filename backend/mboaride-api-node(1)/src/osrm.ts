import { HttpError } from "./errors.js";

export interface LatLng { lat: number; lng: number }
export interface LineString { type: "LineString"; coordinates: [number, number][] }
export interface OsrmLeg { distance_m: number; duration_s: number }
/** `estimated` : itinéraire calculé localement (OSRM injoignable), pas sur le réseau routier. */
export interface OsrmRoute { distance_m: number; duration_s: number; legs: OsrmLeg[]; geometry?: LineString; estimated?: boolean }
export interface OsrmClient {
  route(points: LatLng[], opts?: { geometry?: boolean }): Promise<OsrmRoute>;
}

/** Calcul de repli (Haversine × 1.35 pour le réseau routier de Douala) si OSRM externe est indisponible. */
function haversineMeters(a: LatLng, b: LatLng): number {
  const R = 6371000;
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);
  const h =
      sinLat * sinLat +
      Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinLng * sinLng;
  return 2 * R * Math.asin(Math.sqrt(h)) * 1.35;
}

function buildFallbackRoute(points: LatLng[], includeGeometry?: boolean): OsrmRoute {
  const legs: OsrmLeg[] = [];
  let totalDist = 0;
  let totalDur = 0;

  for (let i = 0; i < points.length - 1; i++) {
    const dist = Math.max(200, Math.round(haversineMeters(points[i], points[i + 1])));
    // Vitesse moyenne urbaine à Douala ~ 24 km/h (6.67 m/s)
    const dur = Math.max(60, Math.round(dist / 6.67));
    legs.push({ distance_m: dist, duration_s: dur });
    totalDist += dist;
    totalDur += dur;
  }

  return {
    distance_m: totalDist,
    duration_s: totalDur,
    estimated: true,
    legs,
    geometry: includeGeometry
        ? {
          type: "LineString",
          coordinates: points.map((p) => [p.lng, p.lat]),
        }
        : undefined,
  };
}

/** Client HTTP du service `route` d'OSRM (profil voiture) avec repli local automatique. */
export function createOsrmClient(baseUrl: string, timeoutMs: number, fetchFn: typeof fetch = fetch): OsrmClient {
  const base = baseUrl.replace(/\/+$/, "");
  return {
    async route(points, opts = {}) {
      if (points.length < 2) {
        throw new HttpError(422, "Au moins deux points sont requis");
      }

      const coords = points.map((p) => `${p.lng},${p.lat}`).join(";");
      const url = `${base}/route/v1/driving/${coords}?overview=${opts.geometry ? "full" : "false"}&geometries=geojson&steps=false`;

      try {
        const res = await fetchFn(url, { signal: AbortSignal.timeout(timeoutMs) });
        const body: any = await res.json();

        if (body?.code === "NoRoute") throw new HttpError(422, "Aucun itinéraire entre ces points");
        if (body?.code === "NoSegment") throw new HttpError(422, "Un des points est trop éloigné d'une route");
        if (!res.ok || body?.code !== "Ok" || !body.routes?.length) {
          return buildFallbackRoute(points, opts.geometry);
        }

        const r = body.routes[0];
        return {
          distance_m: Math.round(r.distance),
          duration_s: Math.round(r.duration),
          legs: r.legs.map((l: any) => ({
            distance_m: Math.round(l.distance),
            duration_s: Math.round(l.duration),
          })),
          geometry: opts.geometry ? r.geometry : undefined,
        };
      } catch (err) {
        if (err instanceof HttpError && err.status === 422) throw err;
        // Repli local automatique au lieu de bloquer avec une 503
        return buildFallbackRoute(points, opts.geometry);
      }
    },
  };
}

/** Cache mémoire : évite de recalculer les mêmes trajets (objectif de convergence < 2 s). */
export function withCache(client: OsrmClient, ttlMs = 10 * 60_000, max = 1000): OsrmClient {
  const store = new Map<string, { at: number; value: OsrmRoute }>();
  return {
    async route(points, opts = {}) {
      const key =
          points.map((p) => `${p.lat.toFixed(5)},${p.lng.toFixed(5)}`).join("|") +
          (opts.geometry ? "#g" : "");
      const hit = store.get(key);
      if (hit && Date.now() - hit.at < ttlMs) return hit.value;
      const value = await client.route(points, opts);
      if (value.estimated) return value; // on retentera OSRM au prochain appel
      if (store.size >= max) store.delete(store.keys().next().value as string);
      store.set(key, { at: Date.now(), value });
      return value;
    },
  };
}