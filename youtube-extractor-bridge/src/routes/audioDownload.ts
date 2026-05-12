import type { NextFunction, Request, Response } from "express";
import { Router } from "express";

import { YouTubeAudioProxyService } from "../services/youtubeAudioProxyService.js";
import { logger } from "../utils/logger.js";

export const createAudioDownloadRouter = (audioProxyService: YouTubeAudioProxyService) => {
  const audioDownloadRouter = Router();
  type AudioDownloadParams = {
    token: string;
  };

  audioDownloadRouter.get(
    "/:token",
    async (
      req: Request<AudioDownloadParams>,
      res: Response,
      next: NextFunction
    ) => {
      try {
        const preparedDownload = await audioProxyService.prepareAudioDownload(req.params.token);
        let cleanedUp = false;

        const cleanup = async () => {
          if (cleanedUp) {
            return;
          }

          cleanedUp = true;
          await preparedDownload.cleanup();
        };

        res.setHeader("Content-Type", "audio/mp4");
        res.setHeader("Content-Disposition", `attachment; filename="${preparedDownload.fileName}"`);

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

        logger.info("youtube_audio_download_streaming", {
          fileName: preparedDownload.fileName,
          filePath: preparedDownload.filePath,
          token: req.params.token
        });

        preparedDownload.stream.pipe(res);
      } catch (error) {
        next(error);
      }
    }
  );

  return audioDownloadRouter;
};
