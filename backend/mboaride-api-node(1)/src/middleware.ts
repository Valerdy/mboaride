import type { NextFunction, Request, Response } from "express";
import type { Knex } from "knex";
import { HttpError } from "./errors.js";
import { decodeAccessToken } from "./security.js";

export interface UserRow {
  id: number;
  email: string | null;
  phone: string | null;
  full_name: string;
  password_hash: string;
  is_verified: boolean | number;
  company_id: number | null;
}
export type AuthedRequest = Request & { user: UserRow };

export const requireAuth = (db: Knex) => async (req: Request, _res: Response, next: NextFunction) => {
  const header = req.headers.authorization ?? "";
  const userId = header.startsWith("Bearer ") ? decodeAccessToken(header.slice(7)) : null;
  const user = userId ? await db<UserRow>("users").where({ id: userId }).first() : undefined;
  if (!user || !user.is_verified) throw new HttpError(401, "Session invalide ou expirée");
  (req as AuthedRequest).user = user;
  next();
};
