export type SupportedProvider = "youtube";
export type MediaType = "audio" | "video";

export interface ResolveRequestBody {
  url: string;
}

export interface DownloadRequestBody {
  url: string;
  title?: string;
  providerItemId?: string;
}

export interface ResolveDownloadRequestBody {
  provider: SupportedProvider;
  providerItemId: string;
  sourcePageURL: string;
  mediaType: MediaType;
}

export interface ResolveDownloadSuccessResponse {
  downloadURL: string;
  mimeType: string;
  fileExtension: string;
  provider: SupportedProvider;
  providerItemId: string;
}

export interface ErrorResponse {
  error: "invalid_request" | "no_downloadable_media" | "extractor_failure";
  message: string;
}

export interface HealthResponse {
  ok: true;
  service: string;
}

export interface APIErrorResponse {
  ok: false;
  error: string;
}

export interface ResolveResponse {
  ok: true;
  provider: SupportedProvider;
  providerItemId: string;
  sourcePageURL: string;
  availableMediaTypes: MediaType[];
  audio: ResolveDownloadSuccessResponse | null;
  video: ResolveDownloadSuccessResponse | null;
}
