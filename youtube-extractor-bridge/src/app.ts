import express from "express";

import { errorHandler, notFoundHandler } from "./middleware/errorHandler.js";
import { requestLogger } from "./middleware/requestLogger.js";
import { apiRouter } from "./routes/api.js";
import { createAudioDownloadRouter } from "./routes/audioDownload.js";
import { healthRouter } from "./routes/health.js";
import { resolveDownloadRouter, youtubeAudioProxyService } from "./routes/resolveDownload.js";

export const createApp = () => {
  const app = express();

  app.use(express.json({ limit: "64kb" }));
  app.use(requestLogger);

  app.use(apiRouter);
  app.use("/health", healthRouter);
  app.use("/resolve-download", resolveDownloadRouter);
  app.use("/downloads/audio", createAudioDownloadRouter(youtubeAudioProxyService));

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
};
