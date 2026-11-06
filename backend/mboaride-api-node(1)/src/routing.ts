import type { LatLng, OsrmClient } from "./osrm.js";

export interface DriverTrip { origin: LatLng; destination: LatLng }

/**
 * Détour imposé à un conducteur pour prendre un passager.
 * Compare son trajet direct (A→B) au trajet avec passager (A→pickup→dropoff→B).
 */
export async function computeDetour(
  osrm: OsrmClient, driver: DriverTrip, pickup: LatLng, dropoff: LatLng, maxDetourS?: number,
) {
  const [base, via] = await Promise.all([
    osrm.route([driver.origin, driver.destination]),
    osrm.route([driver.origin, pickup, dropoff, driver.destination]),
  ]);
  const detour_s = Math.max(0, via.duration_s - base.duration_s);
  const detour_m = Math.max(0, via.distance_m - base.distance_m);
  return {
    base: { distance_m: base.distance_m, duration_s: base.duration_s },
    with_pickup: { distance_m: via.distance_m, duration_s: via.duration_s },
    detour_s,
    detour_m,
    detour_pct: base.duration_s > 0 ? Math.round((detour_s / base.duration_s) * 1000) / 10 : 0,
    pickup_eta_s: via.legs[0].duration_s,          // temps pour rejoindre le passager
    shared_distance_m: via.legs[1].distance_m,     // km partagés : base du prix (US09)
    shared_duration_s: via.legs[1].duration_s,
    within_limit: maxDetourS === undefined ? null : detour_s <= maxDetourS,
  };
}

/** Exécute `fn` sur les éléments par lots, pour ne pas saturer OSRM. */
export async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const out: R[] = [];
  for (let i = 0; i < items.length; i += limit) {
    out.push(...(await Promise.all(items.slice(i, i + limit).map(fn))));
  }
  return out;
}
