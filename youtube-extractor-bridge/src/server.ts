import { createServer } from "node:http";
import { networkInterfaces } from "node:os";

import { createApp } from "./app.js";
import { env } from "./config/env.js";
import { logger } from "./utils/logger.js";

const app = createApp();
const server = createServer(app);

server.listen(env.port, env.host, () => {
  const localHealthURL = `http://127.0.0.1:${env.port}/health`;
  const lanHealthURLs = getLANHealthURLs(env.port);

  logger.info("bridge_started", {
    host: env.host,
    port: env.port,
    nodeEnv: env.nodeEnv,
    localHealthURL,
    lanHealthURLs,
    realDeviceReminder: "Open a LAN health URL from iPhone Safari before testing real-device downloads."
  });

  if (env.host !== "0.0.0.0") {
    logger.warn("bridge_host_not_public", {
      host: env.host,
      message: "Physical iPhone testing requires HOST=0.0.0.0 so the bridge listens on the Mac LAN interface."
    });
  }
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

const getLANHealthURLs = (port: number): string[] => {
  return Object.values(networkInterfaces())
    .flatMap((networkInterface) => networkInterface ?? [])
    .filter((address) => address.family === "IPv4" && !address.internal)
    .map((address) => `http://${address.address}:${port}/health`);
};
