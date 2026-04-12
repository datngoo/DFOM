const parsePort = (value: string | undefined, fallback: number): number => {
  if (!value) {
    return fallback;
  }

  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
};

export const env = {
  host: process.env.HOST?.trim() || "0.0.0.0",
  port: parsePort(process.env.PORT, 8080),
  nodeEnv: process.env.NODE_ENV?.trim() || "development",
  ytDlpPythonPath: process.env.YT_DLP_PYTHON_PATH?.trim() || undefined
} as const;
