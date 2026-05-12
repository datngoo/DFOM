import type { Request, Response } from "express";
import { Router } from "express";

import { InvalidRequestError } from "../errors/httpErrors.js";
import { YouTubeAudioProxyService } from "../services/youtubeAudioProxyService.js";
import { YouTubeExtractorService } from "../services/youtubeExtractorService.js";
import type {
  MediaType,
  ResolveDownloadRequestBody,
  ResolveDownloadSuccessResponse
} from "../types/api.js";

export const resolveDownloadRouter = Router();

export const youtubeAudioProxyService = new YouTubeAudioProxyService();
const youtubeExtractorService = new YouTubeExtractorService(youtubeAudioProxyService);
const supportedMediaTypes = new Set<MediaType>(["audio", "video"]);

resolveDownloadRouter.post("/", async (req: Request, res: Response) => {
  const body = validateResolveDownloadRequest(req.body);
  const host = req.get("host");

  if (!host) {
    throw new InvalidRequestError("Request host header is required.");
  }

  const response: ResolveDownloadSuccessResponse = await youtubeExtractorService.resolveDownload({
    bridgeBaseURL: `${req.protocol}://${host}`,
    providerItemId: body.providerItemId,
    mediaType: body.mediaType,
    sourcePageURL: body.sourcePageURL
  });

  res.status(200).json(response);
});

const validateResolveDownloadRequest = (value: unknown): ResolveDownloadRequestBody => {
  if (!isRecord(value)) {
    throw new InvalidRequestError("Request body must be a JSON object.");
  }

  const provider = typeof value.provider === "string" ? value.provider.trim() : "";
  const providerItemId =
    typeof value.providerItemId === "string" ? value.providerItemId.trim() : "";
  const sourcePageURL =
    typeof value.sourcePageURL === "string" ? value.sourcePageURL.trim() : "";
  const mediaType = typeof value.mediaType === "string" ? value.mediaType.trim() : "";

  if (provider !== "youtube") {
    throw new InvalidRequestError('The "provider" field must be exactly "youtube".');
  }

  if (!providerItemId) {
    throw new InvalidRequestError('The "providerItemId" field is required.');
  }

  if (!sourcePageURL) {
    throw new InvalidRequestError('The "sourcePageURL" field is required.');
  }

  try {
    new URL(sourcePageURL);
  } catch {
    throw new InvalidRequestError('The "sourcePageURL" field must be a valid URL.');
  }

  if (!supportedMediaTypes.has(mediaType as MediaType)) {
    throw new InvalidRequestError('The "mediaType" field must be either "audio" or "video".');
  }

  return {
    provider: "youtube",
    providerItemId,
    sourcePageURL,
    mediaType: mediaType as MediaType
  };
};

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === "object" && value !== null;
};
