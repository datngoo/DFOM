import type { MediaType } from "../types/api.js";

export type CandidateSource = "requested_downloads" | "top_level" | "requested_formats";
export type URLType = "direct_http" | "manifest" | "fragmented" | "missing" | "unknown";

export interface YtDlpFormat {
  url?: string;
  ext?: string;
  format_id?: string;
  format?: string;
  protocol?: string;
  acodec?: string;
  vcodec?: string;
  manifest_url?: string;
  fragments?: Array<{ url?: string }>;
  requested_formats?: YtDlpFormat[];
}

export interface YtDlpInfo extends YtDlpFormat {
  webpage_url?: string;
  requested_formats?: YtDlpFormat[];
  requested_downloads?: YtDlpFormat[];
}

export interface ResolvedDownloadCandidate {
  format: YtDlpFormat;
  url?: string;
  urlSource: CandidateSource;
  urlType: URLType;
}

export interface CandidateSelectionResult {
  selected?: ResolvedDownloadCandidate;
  rejected: Array<{
    candidate: ResolvedDownloadCandidate;
    reason: string;
  }>;
}

const DIRECT_PROTOCOLS = new Set(["http", "https"]);

export const buildFormatSelector = (mediaType: MediaType): string => {
  if (mediaType === "audio") {
    return "bestaudio[ext=m4a]/bestaudio";
  }

  return "best[ext=mp4][protocol^=http][acodec!=none][vcodec!=none]/best[protocol^=http][acodec!=none][vcodec!=none]";
};

export const chooseDownloadCandidate = (
  extraction: YtDlpInfo,
  mediaType: MediaType
): CandidateSelectionResult => {
  const candidates = getResolvedDownloadCandidates(extraction, mediaType);

  const selected = candidates.find((candidate) => Boolean(candidate.url));

  return {
    selected,
    rejected: []
  };
};

export const getResolvedDownloadCandidates = (
  extraction: YtDlpInfo,
  mediaType: MediaType
): ResolvedDownloadCandidate[] => {
  const candidates: ResolvedDownloadCandidate[] = [];

  if (extraction.requested_downloads?.[0]) {
    candidates.push(toCandidate(extraction.requested_downloads[0], "requested_downloads"));
  }

  candidates.push(toCandidate(extraction, "top_level"));

  if (mediaType === "video" && extraction.requested_formats?.[0]) {
    candidates.push(toCandidate(extraction.requested_formats[0], "requested_formats"));
  }

  return dedupeCandidates(candidates);
};

export const getFormatDiagnostics = (candidate: ResolvedDownloadCandidate) => {
  return {
    formatId: candidate.format.format_id,
    ext: candidate.format.ext,
    acodec: candidate.format.acodec,
    vcodec: candidate.format.vcodec,
    protocol: candidate.format.protocol,
    urlType: candidate.urlType,
    urlSource: candidate.urlSource
  };
};

export const inferFileExtension = (format: YtDlpFormat, mediaType: MediaType): string => {
  const extension = normalize(format.ext);

  if (mediaType === "audio" && (extension === "m4a" || extension === "mp4")) {
    return "m4a";
  }

  if (extension) {
    return extension;
  }

  return mediaType === "audio" ? "m4a" : "mp4";
};

export const inferMimeType = (
  format: YtDlpFormat,
  mediaType: MediaType,
  fileExtension: string
): string => {
  const extension = fileExtension.toLowerCase();

  if (extension === "m4a") {
    return "audio/mp4";
  }

  if (extension === "webm") {
    return mediaType === "audio" || normalize(format.vcodec) === "none" ? "audio/webm" : "video/webm";
  }

  if (extension === "mp4") {
    return mediaType === "audio" || normalize(format.vcodec) === "none" ? "audio/mp4" : "video/mp4";
  }

  return "application/octet-stream";
};

const toCandidate = (format: YtDlpFormat, urlSource: CandidateSource): ResolvedDownloadCandidate => {
  return {
    format,
    url: format.url,
    urlSource,
    urlType: classifyURLType(format)
  };
};

const classifyURLType = (format: YtDlpFormat): URLType => {
  if (!format.url) {
    return "missing";
  }

  if (format.fragments?.length) {
    return "fragmented";
  }

  const protocol = normalize(format.protocol);
  const loweredURL = format.url.toLowerCase();
  const hasManifestURL = Boolean(format.manifest_url);
  const looksLikeManifestURL =
    loweredURL.includes(".m3u8") || loweredURL.includes("/manifest/") || loweredURL.includes("manifest.googlevideo");

  if (hasManifestURL || protocol.startsWith("m3u8") || protocol.includes("dash") || looksLikeManifestURL) {
    return "manifest";
  }

  if (DIRECT_PROTOCOLS.has(protocol)) {
    return "direct_http";
  }

  return "unknown";
};

const dedupeCandidates = (candidates: ResolvedDownloadCandidate[]): ResolvedDownloadCandidate[] => {
  const seen = new Set<string>();

  return candidates.filter((candidate) => {
    const key = [
      candidate.urlSource,
      candidate.format.format_id ?? "",
      candidate.format.ext ?? "",
      candidate.format.protocol ?? "",
      candidate.url ?? ""
    ].join("|");

    if (seen.has(key)) {
      return false;
    }

    seen.add(key);
    return true;
  });
};

const normalize = (value: string | undefined): string => {
  return value?.trim().toLowerCase() ?? "";
};
