export type SupportedProvider = "youtube";
export type MediaType = "audio" | "video";

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
  status: "ok";
  service: string;
  port: number;
  timestamp: string;
}
