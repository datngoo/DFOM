import { Router } from "express";

import type { HealthResponse } from "../types/api.js";

export const healthRouter = Router();

healthRouter.get("/", (_req, res) => {
  const payload: HealthResponse = {
    ok: true,
    service: "youtube-extractor-bridge"
  };

  res.status(200).json(payload);
});
