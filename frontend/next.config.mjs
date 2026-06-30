/** @type {import('next').NextConfig} */

const env = process.env.NODE_ENV ?? 'development';
const isDev = env === 'development';

const nextConfig = {
  env: {
    APP_ENV: env,
    DEV_MODE: String(isDev),
  },
};

export default nextConfig;
