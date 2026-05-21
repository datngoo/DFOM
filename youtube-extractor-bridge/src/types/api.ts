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
  error:
    | "invalid_request"
    | "VIDEO_UNAVAILABLE"
    | "VIDEO_PRIVATE"
    | "VIDEO_AGE_RESTRICTED"
    | "FORMAT_UNAVAILABLE"
    | "PROVIDER_BLOCKED"
    | "EXTRACTOR_FAILED";
  message: string;
}

export interface HealthResponse {
  status: "ok";
  service: string;
  host: string;
  port: number;
  timestamp: string;
}
