import type { Request, Response } from "express";
import { Router } from "express";

import type { HealthResponse } from "../types/api.js";

export const healthRouter = Router();

healthRouter.get("/", (_req: Request, res: Response) => {
  const payload: HealthResponse = {
    ok: true,
    service: "youtube-extractor-bridge"
  };

  res.status(200).json(payload);
});
