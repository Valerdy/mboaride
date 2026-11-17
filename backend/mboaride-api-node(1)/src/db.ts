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
  if (target && target !== "memory") mkdirSync(dirname(target), { recursive: true });
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

  // Table users créée AVANT otp_codes et refresh_tokens (clés étrangères vers users.id)
  if (!(await db.schema.hasTable("users"))) {
    await db.schema.createTable("users", (table) => {
      table.increments("id");
      table.string("full_name").notNullable();
      table.string("email").notNullable().unique();
      table.string("phone").notNullable().unique();
      table.string("password_hash").notNullable();
      table.boolean("is_verified").notNullable().defaultTo(false);
      table.string("role").notNullable().defaultTo("passenger");
      table.string("company").nullable();
      table.timestamp("created_at").notNullable().defaultTo(db.fn.now());
      table.timestamp("updated_at").notNullable().defaultTo(db.fn.now());
    });
  } else {
    if (!(await db.schema.hasColumn("users", "email"))) {
      await db.schema.alterTable("users", (t) => t.string("email").nullable().unique());
    }
    if (!(await db.schema.hasColumn("users", "password_hash"))) {
      await db.schema.alterTable("users", (t) => t.string("password_hash").nullable());
    }
    if (!(await db.schema.hasColumn("users", "is_verified"))) {
      await db.schema.alterTable("users", (t) => t.boolean("is_verified").notNullable().defaultTo(false));
    }
    if (!(await db.schema.hasColumn("users", "role"))) {
      await db.schema.alterTable("users", (t) => t.string("role").notNullable().defaultTo("passenger"));
    }
    if (!(await db.schema.hasColumn("users", "company"))) {
      await db.schema.alterTable("users", (t) => t.string("company").nullable());
    }
    if (!(await db.schema.hasColumn("users", "created_at"))) {
      await db.schema.alterTable("users", (t) => t.timestamp("created_at").notNullable().defaultTo(db.fn.now()));
    }
    if (!(await db.schema.hasColumn("users", "updated_at"))) {
      await db.schema.alterTable("users", (t) => t.timestamp("updated_at").notNullable().defaultTo(db.fn.now()));
    }
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

  if (!(await db.schema.hasTable("crews"))) {
    await db.schema.createTable("crews", (table) => {
      table.uuid("id").primary();
      table.string("driver_id").nullable();
      table.string("status").notNullable().defaultTo("forming");
      table.integer("capacity").notNullable().defaultTo(4);
      table.float("origin_lat").notNullable();
      table.float("origin_lng").notNullable();
      table.float("dest_lat").notNullable();
      table.float("dest_lng").notNullable();
      table.timestamp("departure_target").notNullable();
      table.timestamps(true, true);
    });
  }

  if (!(await db.schema.hasTable("ride_requests"))) {
    await db.schema.createTable("ride_requests", (table) => {
      table.uuid("id").primary();
      table.string("user_id").notNullable();
      table.uuid("crew_id").nullable().references("id").inTable("crews").onDelete("SET NULL");
      table.string("pickup_name").notNullable();
      table.float("pickup_lat").notNullable();
      table.float("pickup_lng").notNullable();
      table.string("dropoff_name").notNullable();
      table.float("dropoff_lat").notNullable();
      table.float("dropoff_lng").notNullable();
      table.timestamp("window_start").notNullable();
      table.timestamp("window_end").notNullable();
      table.integer("max_price_fcfa").notNullable();
      table.jsonb("comforts").notNullable().defaultTo("[]");
      table.string("status").notNullable().defaultTo("searching");
      table.timestamps(true, true);
    });
  }

  // 1. Agrément conducteur (Écran 1)
  if (!(await db.schema.hasTable("driver_agreements"))) {
    await db.schema.createTable("driver_agreements", (table) => {
      table.uuid("id").primary();
      table.string("user_id").notNullable().unique();
      table.string("status").notNullable().defaultTo("pending");
      table.jsonb("documents").notNullable().defaultTo("{}");
      table.timestamps(true, true);
    });
  }

  // 2. Comptes élèves (Écran 2 - US17, US19)
  if (!(await db.schema.hasTable("student_accounts"))) {
    await db.schema.createTable("student_accounts", (table) => {
      table.uuid("id").primary();
      table.string("parent_user_id").notNullable();
      table.string("first_name").notNullable();
      table.integer("age").notNullable();
      table.boolean("authorized").notNullable().defaultTo(true);
      table.string("school_route").notNullable();
      table.jsonb("alert_prefs").notNullable().defaultTo('{"onDeparture":true,"onArrival":true,"onDelay":true}');
      table.timestamps(true, true);
    });
  }
  if (!(await db.schema.hasColumn("student_accounts", "paused"))) {
    await db.schema.alterTable("student_accounts", (t) =>
        t.boolean("paused").notNullable().defaultTo(false));
  }

  if (!(await db.schema.hasTable("student_routes"))) {
    await db.schema.createTable("student_routes", (t) => {
      t.uuid("id").primary();
      t.uuid("student_id").notNullable().unique().references("id").inTable("student_accounts").onDelete("CASCADE");
      t.string("pickup_name").notNullable();
      t.string("dropoff_name").notNullable();
      t.jsonb("days").notNullable().defaultTo('["mon","tue","wed","thu","fri"]');
      t.string("depart_time", 5).notNullable().defaultTo("07:00");
      t.timestamps(true, true);
    });
  }

  if (!(await db.schema.hasTable("trusted_contacts"))) {
    await db.schema.createTable("trusted_contacts", (t) => {
      t.uuid("id").primary();
      t.uuid("student_id").notNullable().unique().references("id").inTable("student_accounts").onDelete("CASCADE");
      t.string("name").notNullable();
      t.string("phone").notNullable();
      t.timestamps(true, true);
    });
  }

  // 3. Voyages interurbains (Écran 3 - US21, US22)
  if (!(await db.schema.hasTable("intercity_trips"))) {
    await db.schema.createTable("intercity_trips", (table) => {
      table.uuid("id").primary();
      table.string("driver_id").notNullable();
      table.string("origin_city").notNullable().defaultTo("Douala");
      table.string("destination_city").notNullable().defaultTo("Yaoundé");
      table.string("day_label").notNullable();
      table.string("departure_time").notNullable();
      table.jsonb("pickup_points").notNullable().defaultTo("[]");
      table.integer("total_seats").notNullable().defaultTo(4);
      table.integer("reserved_seats").notNullable().defaultTo(0);
      table.integer("price_per_seat_fcfa").notNullable().defaultTo(3200);
      table.jsonb("pickup_order").notNullable().defaultTo("[]");
      table.string("status").notNullable().defaultTo("published");
      table.timestamps(true, true);
    });
  }
}