import "dotenv/config";

const num = (v: string | undefined, d: number) => (v ? Number(v) : d);

export const config = {
  databaseUrl: process.env.DATABASE_URL ?? "pglite:./data/mboaride",
  secretKey: process.env.SECRET_KEY ?? "change-me-avec-au-moins-32-caracteres",
  port: num(process.env.PORT, 8000),
  accessTokenMinutes: num(process.env.ACCESS_TOKEN_MINUTES, 15),
  refreshTokenDays: num(process.env.REFRESH_TOKEN_DAYS, 7),
  otpMinutes: num(process.env.OTP_MINUTES, 5),
  otpMaxAttempts: num(process.env.OTP_MAX_ATTEMPTS, 5),
  defaultCountryCode: process.env.DEFAULT_COUNTRY_CODE ?? "+237",
  corsOrigin: process.env.CORS_ORIGIN ?? "*",
  rateLimitMax: num(process.env.RATE_LIMIT_MAX, 100),
  // OSRM : serveur local (Docker) ou, pour dépanner, https://router.project-osrm.org (usage léger uniquement)
  osrmUrl: process.env.OSRM_URL ?? "http://localhost:5000",
  osrmTimeoutMs: num(process.env.OSRM_TIMEOUT_MS, 3000),
  // Zone de service (Douala et environs) : sud, nord, ouest, est
  serviceArea: {
    minLat: num(process.env.AREA_MIN_LAT, 3.85),
    maxLat: num(process.env.AREA_MAX_LAT, 4.25),
    minLng: num(process.env.AREA_MIN_LNG, 9.45),
    maxLng: num(process.env.AREA_MAX_LNG, 10.0),
  },
};
