import { Router } from "express";

import { env } from "../config/env.js";
import type { HealthResponse } from "../types/api.js";

export const healthRouter = Router();

healthRouter.get("/", (_req, res) => {
  const payload: HealthResponse = {
    status: "ok",
    service: "youtube-extractor-bridge",
    port: env.port,
    timestamp: new Date().toISOString()
  };

  res.status(200).json(payload);
});
