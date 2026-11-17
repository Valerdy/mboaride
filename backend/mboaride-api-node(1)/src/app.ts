import cors from "cors";
import express, { NextFunction, Request, Response } from "express";
import rateLimit from "express-rate-limit";
import type { Knex } from "knex";
import { ZodError } from "zod";
import { createAgentsRouter } from "./agents.routes.js";
import { authRouter } from "./auth.routes.js";
import { config } from "./config.js";
import { HttpError } from "./errors.js";
import { requireAuth } from "./middleware.js";
import { createOsrmClient, OsrmClient, withCache } from "./osrm.js";
import { routingRouter } from "./routing.routes.js";

/**
 * API Node : authentification (US01) et itinéraires (OSRM). Le métier (demandes, trajets,
 * offres, réservations, comptes élèves, agrément) appartient à l'API Python, qui vérifie
 * les jetons émis ici et partage la même base PostgreSQL (voir docs/decision-backend.md).
 */
export function createApp(db: Knex, opts: { rateLimit?: boolean; osrm?: OsrmClient } = {}) {
  const app = express();
  app.use(
    cors({
      // "*" en développement : accepte l'origine du front (Flutter Web sur un port aléatoire).
      origin: config.corsOrigin === "*" ? true : config.corsOrigin.split(",").map((o) => o.trim()),
      methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
      allowedHeaders: ["Content-Type", "Authorization"],
    }),
  );
  app.use(express.json());
  if (process.env.NODE_ENV !== "test") {
    app.use((req, res, next) => {
      const t = Date.now();
      res.on("finish", () => console.log(req.method, req.url, res.statusCode, `${Date.now() - t}ms`));
      next();
    });
  }
  app.get("/health", (_req, res) => res.json({ status: "ok" }));
  if (opts.rateLimit !== false) {
    app.use("/auth", rateLimit({ windowMs: 15 * 60_000, limit: config.rateLimitMax, standardHeaders: true, legacyHeaders: false }));
  }
  app.use("/auth", authRouter(db));
  const osrm = opts.osrm ?? withCache(createOsrmClient(config.osrmUrl, config.osrmTimeoutMs));
  app.use("/routes", routingRouter(db, osrm));
  app.use("/routes", createAgentsRouter(db, requireAuth(db)));
  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof HttpError) return res.status(err.status).json({ detail: err.message });
    if (err instanceof ZodError) return res.status(422).json({ detail: err.issues.map((i) => i.message).join(", ") });
    if ((err as { type?: string })?.type === "entity.parse.failed") return res.status(400).json({ detail: "JSON invalide" });
    console.error(err);
    res.status(500).json({ detail: "Erreur interne" });
  });
  return app;
}
