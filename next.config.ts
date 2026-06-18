import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  serverExternalPackages: ["better-sqlite3", "yahoo-finance2"],
  turbopack: {},
};

export default nextConfig;
