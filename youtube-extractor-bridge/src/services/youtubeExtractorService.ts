import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { promisify } from "node:util";

import { env } from "../config/env.js";
import {
  ExtractorFailureError,
  HttpError,
  InternalExtractorError,
  NoDownloadableMediaError,
  ProviderBlockedError,
  VideoAgeRestrictedError,
  VideoPrivateError,
  VideoUnavailableError
} from "../errors/httpErrors.js";
import {
  buildFormatSelector,
  chooseDownloadCandidate,
  getFormatDiagnostics,
  inferFileExtension,
  inferMimeType,
  type YtDlpInfo
} from "./youtubeFormatSelection.js";
import { YouTubeAudioProxyService } from "./youtubeAudioProxyService.js";
import type { MediaType, ResolveDownloadSuccessResponse } from "../types/api.js";
import { logger } from "../utils/logger.js";

const execFileAsync = promisify(execFile);

interface ResolveYouTubeDownloadInput {
  bridgeBaseURL: string;
  providerItemId: string;
  mediaType: MediaType;
  sourcePageURL: string;
}

export class YouTubeExtractorService {
  constructor(private readonly audioProxyService: YouTubeAudioProxyService) {}

  public async resolveDownload(
    input: ResolveYouTubeDownloadInput
  ): Promise<ResolveDownloadSuccessResponse> {
    try {
      const extraction = await this.extractMedia(input);

      if (input.mediaType === "audio") {
        logger.info("youtube_audio_source_selected", {
          providerItemId: input.providerItemId,
          mediaType: input.mediaType,
          formatId: extraction.format_id,
          format: extraction.format,
          ext: extraction.ext,
          acodec: extraction.acodec,
          vcodec: extraction.vcodec,
          protocol: extraction.protocol,
          sourcePageURL: input.sourcePageURL
        });

        return {
          downloadURL: this.audioProxyService.createDownloadURL({
            bridgeBaseURL: input.bridgeBaseURL,
            providerItemId: input.providerItemId,
            sourcePageURL: input.sourcePageURL
          }),
          mimeType: "audio/mp4",
          fileExtension: "m4a",
          provider: "youtube",
          providerItemId: input.providerItemId
        };
      }

      const selectedCandidate = this.selectVideoDownloadCandidate(extraction);
      const fileExtension = inferFileExtension(selectedCandidate.format, input.mediaType);
      const mimeType = inferMimeType(selectedCandidate.format, input.mediaType, fileExtension);

      logger.info("youtube_media_resolved", {
        providerItemId: input.providerItemId,
        mediaType: input.mediaType,
        mimeType,
        fileExtension,
        format: selectedCandidate.format.format,
        ...getFormatDiagnostics(selectedCandidate),
        sourcePageURL: input.sourcePageURL
      });

      return {
        downloadURL: selectedCandidate.url,
        mimeType,
        fileExtension,
        provider: "youtube",
        providerItemId: input.providerItemId
      };
    } catch (error) {
      if (error instanceof HttpError) {
        throw error;
      }

      throw new InternalExtractorError("The extractor failed unexpectedly while resolving media.");
    }
  }

  private async extractMedia(input: ResolveYouTubeDownloadInput): Promise<YtDlpInfo> {
    const format = buildFormatSelector(input.mediaType);
    const args = [
      resolveYtDlpPath(),
      input.sourcePageURL,
      "--dump-single-json",
      "--no-warnings",
      "--no-playlist",
      "--no-check-certificates",
      "--skip-download",
      "--format",
      format
    ];

    try {
      const { stdout } = await execFileAsync(resolvePythonBinary(), args, {
        env: {
          ...process.env,
          PATH: buildExecutablePath()
        },
        maxBuffer: 10 * 1024 * 1024
      });

      return JSON.parse(stdout) as YtDlpInfo;
    } catch (error) {
      const message = extractProcessErrorMessage(error);
      throw classifyYouTubeExtractorError(message, input.mediaType);
    }
  }

  private selectVideoDownloadCandidate(extraction: YtDlpInfo): {
    format: NonNullable<ReturnType<typeof chooseDownloadCandidate>["selected"]>["format"];
    url: string;
    urlSource: NonNullable<ReturnType<typeof chooseDownloadCandidate>["selected"]>["urlSource"];
    urlType: NonNullable<ReturnType<typeof chooseDownloadCandidate>["selected"]>["urlType"];
  } {
    const selectionResult = chooseDownloadCandidate(extraction, "video");

    if (!selectionResult.selected?.url) {
      throw new NoDownloadableMediaError(
        "No downloadable progressive video stream is available for this YouTube item."
      );
    }

    return {
      ...selectionResult.selected,
      url: selectionResult.selected.url
    };
  }

}

export const classifyYouTubeExtractorError = (message: string, mediaType: MediaType): HttpError => {
  const loweredMessage = message.toLowerCase();

  if (loweredMessage.includes("private video") || loweredMessage.includes("this video is private")) {
    return new VideoPrivateError();
  }

  if (
    loweredMessage.includes("age-restricted") ||
    loweredMessage.includes("age restricted") ||
    loweredMessage.includes("confirm your age")
  ) {
    return new VideoAgeRestrictedError();
  }

  if (
    loweredMessage.includes("this video is not available") ||
    loweredMessage.includes("video unavailable") ||
    loweredMessage.includes("has been removed") ||
    loweredMessage.includes("removed by the uploader") ||
    loweredMessage.includes("deleted")
  ) {
    return new VideoUnavailableError();
  }

  if (
    loweredMessage.includes("requested format is not available") ||
    loweredMessage.includes("requested format not available") ||
    loweredMessage.includes("no video formats found") ||
    loweredMessage.includes("unsupported url") ||
    loweredMessage.includes("drm") ||
    loweredMessage.includes("only images are available for download")
  ) {
    return new NoDownloadableMediaError(
      mediaType === "audio"
        ? "No downloadable audio stream is available for this YouTube item."
        : "No downloadable progressive video stream is available for this YouTube item."
    );
  }

  if (
    loweredMessage.includes("sign in to confirm you're not a bot") ||
    loweredMessage.includes("sign in to confirm you’re not a bot") ||
    loweredMessage.includes("captcha") ||
    loweredMessage.includes("too many requests") ||
    loweredMessage.includes("http error 429") ||
    loweredMessage.includes("blocked")
  ) {
    return new ProviderBlockedError();
  }

  return new ExtractorFailureError("This YouTube video is unavailable or cannot be downloaded.");
};

const buildExecutablePath = (): string => {
  const preferredPrefixes = ["/opt/homebrew/bin", "/usr/local/bin"];
  const currentPath = process.env.PATH ?? "";

  return [...preferredPrefixes, currentPath].filter(Boolean).join(":");
};

const resolvePythonBinary = (): string => {
  const configuredPath = env.ytDlpPythonPath;

  if (configuredPath) {
    return configuredPath;
  }

  const candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"];
  const discovered = candidates.find((candidate) => existsSync(candidate));

  return discovered ?? "python3";
};

const resolveYtDlpPath = (): string => {
  return path.resolve(process.cwd(), "node_modules", "youtube-dl-exec", "bin", "yt-dlp");
};

const extractProcessErrorMessage = (error: unknown): string => {
  if (isProcessError(error)) {
    return error.stderr?.trim() || error.stdout?.trim() || error.message;
  }

  return error instanceof Error ? error.message : "Unknown extraction failure.";
};

const isProcessError = (
  error: unknown
): error is Error & { stderr?: string; stdout?: string } => {
  return error instanceof Error;
};
