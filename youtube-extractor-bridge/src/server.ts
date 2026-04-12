import { createServer } from "node:http";

import { createApp } from "./app.js";
import { env } from "./config/env.js";
import { logger } from "./utils/logger.js";

const app = createApp();
const server = createServer(app);

server.listen(env.port, env.host, () => {
  logger.info("bridge_started", {
    host: env.host,
    port: env.port,
    nodeEnv: env.nodeEnv
  });
});

const shutdown = (signal: NodeJS.Signals) => {
  logger.info("bridge_stopping", { signal });
  server.close(() => {
    logger.info("bridge_stopped");
    process.exit(0);
  });
};

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
