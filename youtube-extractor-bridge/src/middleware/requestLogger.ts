import type { Request, Response, NextFunction } from "express";

import { logger } from "../utils/logger.js";

export const requestLogger = (req: Request, res: Response, next: NextFunction): void => {
  const startedAt = Date.now();

  res.on("finish", () => {
    logger.info("request_completed", {
      method: req.method,
      path: req.originalUrl,
      statusCode: res.statusCode,
      durationMs: Date.now() - startedAt,
      userAgent: req.get("user-agent") ?? "unknown"
    });
  });

  next();
};
