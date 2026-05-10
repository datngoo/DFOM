import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createReadStream, existsSync } from "node:fs";
import { mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";

import { env } from "../config/env.js";
import { ExtractorFailureError, InvalidRequestError } from "../errors/httpErrors.js";
import { logger } from "../utils/logger.js";

const execFileAsync = promisify(execFile);
const AUDIO_PROXY_TTL_MS = 15 * 60 * 1000;

interface AudioDownloadTicket {
  providerItemId: string;
  sourcePageURL: string;
  expiresAt: number;
  title?: string;
}

export interface PreparedAudioDownload {
  cleanup: () => Promise<void>;
  fileName: string;
  filePath: string;
  stream: ReturnType<typeof createReadStream>;
}

export class YouTubeAudioProxyService {
  private readonly tickets = new Map<string, AudioDownloadTicket>();

  public createDownloadURL(input: {
    bridgeBaseURL: string;
    providerItemId: string;
    sourcePageURL: string;
  }): string {
    this.cleanupExpiredTickets();

    const token = randomUUID();
    this.tickets.set(token, {
      providerItemId: input.providerItemId,
      sourcePageURL: input.sourcePageURL,
      expiresAt: Date.now() + AUDIO_PROXY_TTL_MS
    });

    return `${normalizeBaseURL(input.bridgeBaseURL)}/downloads/audio/${token}`;
  }

  public async prepareAudioDownload(token: string): Promise<PreparedAudioDownload> {
    this.cleanupExpiredTickets();

    const ticket = this.getTicket(token);
    return this.prepareAudioDownloadForTicket(ticket);
  }

  public async prepareAudioDownloadFromSource(input: {
    providerItemId: string;
    sourcePageURL: string;
    title?: string;
  }): Promise<PreparedAudioDownload> {
    return this.prepareAudioDownloadForTicket({
      providerItemId: input.providerItemId,
      sourcePageURL: input.sourcePageURL,
      expiresAt: Date.now() + AUDIO_PROXY_TTL_MS,
      ...(input.title ? { title: input.title } : {})
    });
  }

  private async prepareAudioDownloadForTicket(
    ticket: AudioDownloadTicket
  ): Promise<PreparedAudioDownload> {
    const workDirectory = await mkdtemp(path.join(tmpdir(), "youtube-extractor-bridge-audio-"));
    const outputTemplate = path.join(workDirectory, "download.%(ext)s");
    const ytDlpArgs = buildAudioDownloadArgs(ticket.sourcePageURL, outputTemplate);

    logger.info("youtube_audio_download_preparing", {
      providerItemId: ticket.providerItemId,
      sourcePageURL: ticket.sourcePageURL,
      ytDlpArgs
    });

    try {
      await execFileAsync(resolvePythonBinary(), ytDlpArgs, {
        env: {
          ...process.env,
          PATH: buildExecutablePath()
        },
        maxBuffer: 20 * 1024 * 1024
      });

      const filePath = await findPreparedAudioFile(workDirectory);
      const stream = createReadStream(filePath);

      return {
        cleanup: async () => {
          await rm(workDirectory, { recursive: true, force: true });
        },
        fileName: `${sanitizeFileName(ticket.title ?? ticket.providerItemId)}.m4a`,
        filePath,
        stream
      };
    } catch (error) {
      await rm(workDirectory, { recursive: true, force: true });
      throw new ExtractorFailureError(`YouTube audio preparation failed: ${extractProcessErrorMessage(error)}`);
    }
  }

  private getTicket(token: string): AudioDownloadTicket {
    const ticket = this.tickets.get(token);

    if (!ticket || ticket.expiresAt < Date.now()) {
      this.tickets.delete(token);
      throw new InvalidRequestError("Audio download ticket is invalid or expired.");
    }

    return ticket;
  }

  private cleanupExpiredTickets(): void {
    const now = Date.now();

    for (const [token, ticket] of this.tickets.entries()) {
      if (ticket.expiresAt < now) {
        this.tickets.delete(token);
      }
    }
  }
}

export const buildAudioDownloadArgs = (sourcePageURL: string, outputTemplate: string): string[] => {
  return [
    resolveYtDlpPath(),
    "--no-playlist",
    "--no-part",
    "--no-warnings",
    "--extract-audio",
    "--audio-format",
    "m4a",
    "--audio-quality",
    "0",
    "--output",
    outputTemplate,
    sourcePageURL
  ];
};

const findPreparedAudioFile = async (workDirectory: string): Promise<string> => {
  const files = await readdir(workDirectory);
  const audioFile = files.find((file) => file.toLowerCase().endsWith(".m4a"));

  if (!audioFile) {
    throw new ExtractorFailureError("yt-dlp did not produce a remuxed M4A file.");
  }

  return path.join(workDirectory, audioFile);
};

const sanitizeFileName = (value: string): string => {
  return value.replace(/[^a-zA-Z0-9._-]/g, "_");
};

const normalizeBaseURL = (value: string): string => {
  return value.endsWith("/") ? value.slice(0, -1) : value;
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
  if (error instanceof Error) {
    const processLikeError = error as Error & { stderr?: string; stdout?: string };
    return processLikeError.stderr?.trim() || processLikeError.stdout?.trim() || error.message;
  }

  return "Unknown audio preparation failure.";
};
