import type { NextFunction, Request, Response } from "express";

import { HttpError, InternalExtractorError } from "../errors/httpErrors.js";
import type { ErrorResponse } from "../types/api.js";
import { logger } from "../utils/logger.js";

export const notFoundHandler = (_req: Request, res: Response<ErrorResponse>): void => {
  res.status(404).json({
    error: "invalid_request",
    message: "Route not found."
  });
};

export const errorHandler = (
  error: unknown,
  req: Request,
  res: Response<ErrorResponse>,
  _next: NextFunction
): void => {
  const httpError =
    error instanceof HttpError
      ? error
      : new InternalExtractorError("The extractor failed unexpectedly while resolving media.");

  logger.error("request_failed", {
    method: req.method,
    path: req.originalUrl,
    statusCode: httpError.statusCode,
    errorCode: httpError.errorCode,
    message: httpError.message,
    stack: error instanceof Error ? error.stack : undefined
  });

  res.status(httpError.statusCode).json({
    error: httpError.errorCode,
    message: httpError.message
  });
};
