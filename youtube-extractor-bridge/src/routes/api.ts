import { Readable } from "node:stream";

import type { Request, Response, NextFunction } from "express";
import { Router } from "express";

import {
  ExtractorFailureError,
  InvalidRequestError,
  NoDownloadableMediaError
} from "../errors/httpErrors.js";
import { youtubeAudioProxyService } from "./resolveDownload.js";
import { YouTubeExtractorService } from "../services/youtubeExtractorService.js";
import type {
  DownloadRequestBody,
  ResolveDownloadSuccessResponse,
  ResolveRequestBody,
  ResolveResponse
} from "../types/api.js";
import { logger } from "../utils/logger.js";

export const apiRouter = Router();

const youtubeExtractorService = new YouTubeExtractorService(youtubeAudioProxyService);

apiRouter.post("/resolve", async (req: Request, res: Response) => {
  res.locals.apiResponseShape = "standard";
  const body = validateResolveBody(req.body);
  const providerItemId = inferProviderItemId(body.url);
  const bridgeBaseURL = buildBridgeBaseURL(req);

  logRequestStart("api_resolve_started", req, { providerItemId, sourcePageURL: body.url });

  const [audioResult, videoResult] = await Promise.all([
    resolveVariant({
      bridgeBaseURL,
      mediaType: "audio",
      providerItemId,
      sourcePageURL: body.url
    }),
    resolveVariant({
      bridgeBaseURL,
      mediaType: "video",
      providerItemId,
      sourcePageURL: body.url
    })
  ]);

  if (!audioResult && !videoResult) {
    throw new NoDownloadableMediaError(
      "No downloadable audio or video media is available for this YouTube item."
    );
  }

  const availableMediaTypes: ResolveResponse["availableMediaTypes"] = [];
  if (audioResult) {
    availableMediaTypes.push("audio");
  }
  if (videoResult) {
    availableMediaTypes.push("video");
  }

  const response: ResolveResponse = {
    ok: true,
    provider: "youtube",
    providerItemId,
    sourcePageURL: body.url,
    availableMediaTypes,
    audio: audioResult,
    video: videoResult
  };

  logger.info("api_resolve_succeeded", {
    providerItemId,
    sourcePageURL: body.url,
    availableMediaTypes
  });

  res.status(200).json(response);
});

apiRouter.post(
  "/download/audio",
  async (req: Request, res: Response, next: NextFunction) => {
    res.locals.apiResponseShape = "standard";
    const body = validateDownloadBody(req.body);
    const providerItemId = normalizedString(body.providerItemId) ?? inferProviderItemId(body.url);
    const title = normalizedString(body.title);

    logRequestStart("api_audio_download_started", req, {
      providerItemId,
      sourcePageURL: body.url,
      title
    });

    try {
      const preparedDownload = await youtubeAudioProxyService.prepareAudioDownloadFromSource({
        providerItemId,
        sourcePageURL: body.url,
        title
      });
      let cleanedUp = false;

      const cleanup = async () => {
        if (cleanedUp) {
          return;
        }

        cleanedUp = true;
        await preparedDownload.cleanup();
      };

      res.setHeader("Content-Type", "audio/mp4");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="${preparedDownload.fileName}"`
      );

      preparedDownload.stream.on("error", async (error) => {
        await cleanup();
        next(error);
      });

      preparedDownload.stream.on("close", async () => {
        await cleanup();
      });

      res.on("close", async () => {
        await cleanup();
      });

      logger.info("api_audio_download_succeeded", {
        providerItemId,
        sourcePageURL: body.url,
        fileName: preparedDownload.fileName
      });

      preparedDownload.stream.pipe(res);
    } catch (error) {
      next(error);
    }
  }
);

apiRouter.post(
  "/download/video",
  async (req: Request, res: Response, next: NextFunction) => {
    res.locals.apiResponseShape = "standard";
    const body = validateDownloadBody(req.body);
    const providerItemId = normalizedString(body.providerItemId) ?? inferProviderItemId(body.url);
    const title = normalizedString(body.title);

    logRequestStart("api_video_download_started", req, {
      providerItemId,
      sourcePageURL: body.url,
      title
    });

    try {
      const resolvedVideo = await youtubeExtractorService.resolveDownload({
        bridgeBaseURL: buildBridgeBaseURL(req),
        providerItemId,
        mediaType: "video",
        sourcePageURL: body.url
      });

      await streamResolvedDownload({
        download: resolvedVideo,
        fallbackFileNameBase: title ?? providerItemId,
        res
      });

      logger.info("api_video_download_succeeded", {
        providerItemId,
        sourcePageURL: body.url,
        downloadURL: resolvedVideo.downloadURL
      });
    } catch (error) {
      next(error);
    }
  }
);

const validateResolveBody = (value: unknown): ResolveRequestBody => {
  if (!isRecord(value)) {
    throw new InvalidRequestError("Request body must be a JSON object.");
  }

  const url = normalizedString(typeof value.url === "string" ? value.url : undefined);
  if (!url) {
    throw new InvalidRequestError('The "url" field is required.');
  }

  validateURL(url);
  return { url };
};

const validateDownloadBody = (value: unknown): DownloadRequestBody => {
  if (!isRecord(value)) {
    throw new InvalidRequestError("Request body must be a JSON object.");
  }

  const url = normalizedString(typeof value.url === "string" ? value.url : undefined);
  if (!url) {
    throw new InvalidRequestError('The "url" field is required.');
  }

  validateURL(url);

  const title = normalizedString(typeof value.title === "string" ? value.title : undefined);
  const providerItemId = normalizedString(
    typeof value.providerItemId === "string" ? value.providerItemId : undefined
  );

  return {
    url,
    ...(title ? { title } : {}),
    ...(providerItemId ? { providerItemId } : {})
  };
};

const resolveVariant = async (input: {
  bridgeBaseURL: string;
  mediaType: "audio" | "video";
  providerItemId: string;
  sourcePageURL: string;
}): Promise<ResolveDownloadSuccessResponse | null> => {
  try {
    return await youtubeExtractorService.resolveDownload(input);
  } catch (error) {
    if (error instanceof NoDownloadableMediaError) {
      return null;
    }

    throw error;
  }
};

const streamResolvedDownload = async (input: {
  download: ResolveDownloadSuccessResponse;
  fallbackFileNameBase: string;
  res: Response;
}): Promise<void> => {
  const upstreamResponse = await fetch(input.download.downloadURL);
  if (!upstreamResponse.ok || !upstreamResponse.body) {
    throw new ExtractorFailureError(
      `Upstream video download failed with HTTP ${upstreamResponse.status}.`
    );
  }

  const extension = inferDownloadExtension(input.download.fileExtension, input.download.mimeType);
  const fileName = `${sanitizeFileName(input.fallbackFileNameBase)}.${extension}`;
  const contentType =
    upstreamResponse.headers.get("content-type") ??
    input.download.mimeType ??
    "application/octet-stream";

  input.res.status(200);
  input.res.setHeader("Content-Type", contentType);
  input.res.setHeader("Content-Disposition", `attachment; filename="${fileName}"`);

  const stream = Readable.fromWeb(upstreamResponse.body as globalThis.ReadableStream<Uint8Array>);

  await new Promise<void>((resolve, reject) => {
    stream.on("error", reject);
    input.res.on("finish", resolve);
    input.res.on("close", resolve);
    stream.pipe(input.res);
  });
};

const logRequestStart = (
  message: string,
  req: Request,
  meta: Record<string, unknown>
): void => {
  logger.info(message, {
    method: req.method,
    path: req.originalUrl,
    userAgent: req.get("user-agent") ?? "unknown",
    ...meta
  });
};

const buildBridgeBaseURL = (req: Request): string => {
  const host = req.get("host");
  if (!host) {
    throw new InvalidRequestError("Request host header is required.");
  }

  return `${req.protocol}://${host}`;
};

const validateURL = (value: string): void => {
  try {
    new URL(value);
  } catch {
    throw new InvalidRequestError('The "url" field must be a valid URL.');
  }
};

const inferProviderItemId = (value: string): string => {
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase();

    if (host === "youtu.be") {
      const pathValue = url.pathname.replace(/^\/+/, "");
      if (pathValue) {
        return sanitizeFileName(pathValue);
      }
    }

    if (host.includes("youtube.com")) {
      const watchValue = normalizedString(url.searchParams.get("v") ?? undefined);
      if (watchValue) {
        return sanitizeFileName(watchValue);
      }

      const pathSegments = url.pathname.split("/").filter(Boolean);
      const trailingSegment = pathSegments[pathSegments.length - 1];
      if (trailingSegment) {
        return sanitizeFileName(trailingSegment);
      }
    }
  } catch {
    // Fall through to sanitized URL fallback below.
  }

  return sanitizeFileName(value).slice(0, 120) || "youtube-media";
};

const inferDownloadExtension = (fileExtension?: string, mimeType?: string): string => {
  const normalizedExtension = normalizedString(fileExtension)?.replace(/^\./, "").toLowerCase();
  if (normalizedExtension) {
    return normalizedExtension;
  }

  switch (mimeType?.toLowerCase()) {
    case "video/mp4":
      return "mp4";
    case "video/webm":
      return "webm";
    default:
      return "bin";
  }
};

const sanitizeFileName = (value: string): string => {
  return value.replace(/[^a-zA-Z0-9._-]/g, "_") || "download";
};

const normalizedString = (value: string | undefined): string | undefined => {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
};

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === "object" && value !== null;
};
