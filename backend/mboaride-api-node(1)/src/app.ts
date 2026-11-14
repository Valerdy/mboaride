import cors from "cors";
import express, { NextFunction, Request, Response } from "express";
import rateLimit from "express-rate-limit";
import type { Knex } from "knex";
import { ZodError } from "zod";
import { authRouter } from "./auth.routes.js";
import { config } from "./config.js";
import { HttpError } from "./errors.js";
import { createOsrmClient, OsrmClient, withCache } from "./osrm.js";
import { routingRouter } from "./routing.routes.js";
import { createAgentsRouter } from './agents.routes.js';
import {requireAuth} from "./middleware.js";

export function createApp(db: Knex, opts: { rateLimit?: boolean; osrm?: OsrmClient } = {}) {
  const app = express();
  app.use(cors({ origin: config.corsOrigin }));
  app.use(express.json());
  app.get("/health", (_req, res) => res.json({ status: "ok" }));
  if (opts.rateLimit !== false) {
    app.use("/auth", rateLimit({ windowMs: 15 * 60_000, limit: config.rateLimitMax, standardHeaders: true, legacyHeaders: false }));
  }
  app.use("/auth", authRouter(db));
  const osrm = opts.osrm ?? withCache(createOsrmClient(config.osrmUrl, config.osrmTimeoutMs));
  app.use("/routes", routingRouter(db, osrm));
  app.use('/routes', createAgentsRouter(db, requireAuth));
  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof HttpError) return res.status(err.status).json({ detail: err.message });
    if (err instanceof ZodError) return res.status(422).json({ detail: err.issues.map((i) => i.message).join(", ") });
    if ((err as { type?: string })?.type === "entity.parse.failed") return res.status(400).json({ detail: "JSON invalide" });
    console.error(err);
    res.status(500).json({ detail: "Erreur interne" });
  });
  return app;
}