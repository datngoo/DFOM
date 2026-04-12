import type { ErrorResponse } from "../types/api.js";

export class HttpError extends Error {
  public readonly statusCode: number;
  public readonly errorCode: ErrorResponse["error"];

  constructor(statusCode: number, errorCode: ErrorResponse["error"], message: string) {
    super(message);
    this.name = this.constructor.name;
    this.statusCode = statusCode;
    this.errorCode = errorCode;
  }
}

export class InvalidRequestError extends HttpError {
  constructor(message: string) {
    super(400, "invalid_request", message);
  }
}

export class NoDownloadableMediaError extends HttpError {
  constructor(message: string) {
    super(422, "no_downloadable_media", message);
  }
}

export class ExtractorFailureError extends HttpError {
  constructor(message: string) {
    super(500, "extractor_failure", message);
  }
}
