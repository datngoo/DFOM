import test from "node:test";
import assert from "node:assert/strict";

import {
  buildFormatSelector,
  chooseDownloadCandidate,
  inferFileExtension,
  inferMimeType
} from "../dist/services/youtubeFormatSelection.js";
import { buildAudioDownloadArgs } from "../dist/services/youtubeAudioProxyService.js";

test("audio probe selector prefers bestaudio m4a first", () => {
  assert.match(buildFormatSelector("audio"), /ext=m4a/);
  assert.match(buildFormatSelector("audio"), /bestaudio/);
});

test("video selection still prefers direct progressive downloads", () => {
  const extraction = {
    format_id: "18",
    format: "18 - 640x360 (360p)",
    ext: "mp4",
    acodec: "mp4a.40.2",
    vcodec: "avc1.42001E",
    protocol: "https",
    url: "https://rr.example.com/video.mp4",
    requested_downloads: [
      {
        format_id: "18",
        ext: "mp4",
        acodec: "mp4a.40.2",
        vcodec: "avc1.42001E",
        protocol: "https",
        url: "https://rr.example.com/video.mp4"
      }
    ]
  };

  const result = chooseDownloadCandidate(extraction, "video");

  assert.ok(result.selected);
  assert.equal(result.selected.urlType, "direct_http");
  assert.equal(result.selected.format.format_id, "18");
  assert.equal(inferFileExtension(result.selected.format, "video"), "mp4");
  assert.equal(inferMimeType(result.selected.format, "video", "mp4"), "video/mp4");
});

test("audio download command remuxes into a proper m4a file", () => {
  const args = buildAudioDownloadArgs(
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    "/tmp/test-output.%(ext)s"
  );

  assert.deepEqual(args.slice(1), [
    "--no-playlist",
    "--no-part",
    "--no-warnings",
    "--extract-audio",
    "--audio-format",
    "m4a",
    "--audio-quality",
    "0",
    "--output",
    "/tmp/test-output.%(ext)s",
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  ]);
  assert.match(args[0], /youtube-dl-exec\/bin\/yt-dlp$/);
});
