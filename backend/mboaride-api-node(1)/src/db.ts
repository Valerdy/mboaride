import knex, { Knex } from "knex";
import ClientPgLite from "knex-pglite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

/**
 * - `postgres://...`  : PostgreSQL (production, Docker).
 * - `pglite:./data`   : PGlite, un vrai PostgreSQL en WebAssembly, stocké dans un dossier.
 *                       Aucune installation ni compilation : idéal en local.
 * - `pglite:memory`   : en mémoire (tests).
 */
export function createDb(url: string): Knex {
  if (url.startsWith("postgres")) {
    return knex({ client: "pg", connection: url });
  }
  const target = url.replace(/^pglite:/, "");
  if (target && target !== "memory") mkdirSync(dirname(target), { recursive: true }); // PGlite ne crée pas le dossier parent
  return knex({
    client: ClientPgLite,
    dialect: "postgres",
    connection: target && target !== "memory" ? { filename: target } : {},
  });
}

/** Crée les tables si elles n'existent pas (en production : passer à des migrations versionnées). */
export async function migrate(db: Knex): Promise<void> {
  if (!(await db.schema.hasTable("companies"))) {
    await db.schema.createTable("companies", (t) => {
      t.increments("id");
      t.string("name", 120).notNullable();
      t.string("email_domain", 120).notNullable().unique();
    });
  }
  if (!(await db.schema.hasTable("users"))) {
    await db.schema.createTable("users", (t) => {
      t.increments("id");
      t.string("email", 254).unique();
      t.string("phone", 20).unique();
      t.string("full_name", 120).notNullable();
      t.string("password_hash", 255).notNullable();
      t.boolean("is_verified").notNullable().defaultTo(false);
      t.integer("company_id").references("companies.id");
      t.bigInteger("created_at").notNullable();
    });
  }
  if (!(await db.schema.hasTable("otp_codes"))) {
    await db.schema.createTable("otp_codes", (t) => {
      t.increments("id");
      t.integer("user_id").notNullable().references("users.id").index();
      t.string("code_hash", 64).notNullable();
      t.bigInteger("expires_at").notNullable();
      t.integer("attempts").notNullable().defaultTo(0);
      t.boolean("consumed").notNullable().defaultTo(false);
    });
  }
  if (!(await db.schema.hasTable("refresh_tokens"))) {
    await db.schema.createTable("refresh_tokens", (t) => {
      t.increments("id");
      t.integer("user_id").notNullable().references("users.id").index();
      t.string("token_hash", 64).notNullable().unique();
      t.bigInteger("expires_at").notNullable();
      t.boolean("revoked").notNullable().defaultTo(false);
    });
  }
}
