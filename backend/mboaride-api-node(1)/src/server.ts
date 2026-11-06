import { createApp } from "./app.js";
import { config } from "./config.js";
import { createDb, migrate } from "./db.js";

const db = createDb(config.databaseUrl);
await migrate(db);
createApp(db).listen(config.port, () => console.log(`MboaRide API sur http://localhost:${config.port}`));
