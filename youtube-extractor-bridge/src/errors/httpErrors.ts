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
    super(422, "FORMAT_UNAVAILABLE", message);
  }
}

export class VideoUnavailableError extends HttpError {
  constructor(message = "This YouTube video is unavailable or cannot be downloaded.") {
    super(410, "VIDEO_UNAVAILABLE", message);
  }
}

export class VideoPrivateError extends HttpError {
  constructor(message = "This YouTube video is private or cannot be downloaded.") {
    super(404, "VIDEO_PRIVATE", message);
  }
}

export class VideoAgeRestrictedError extends HttpError {
  constructor(message = "This YouTube video is age restricted and cannot be downloaded.") {
    super(422, "VIDEO_AGE_RESTRICTED", message);
  }
}

export class ProviderBlockedError extends HttpError {
  constructor(message = "YouTube blocked the extractor request. Try again later.") {
    super(422, "PROVIDER_BLOCKED", message);
  }
}

export class ExtractorFailureError extends HttpError {
  constructor(message: string) {
    super(422, "EXTRACTOR_FAILED", message);
  }
}

export class InternalExtractorError extends HttpError {
  constructor(message = "The extractor failed unexpectedly while resolving media.") {
    super(500, "EXTRACTOR_FAILED", message);
  }
}
