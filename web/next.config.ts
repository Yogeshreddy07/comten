import type { NextConfig } from 'next';
const config: NextConfig = {
  poweredByHeader: false,
  outputFileTracingIncludes: {'/*':['./legacy/**/*.html']},
  async rewrites() {
    return [{source:'/api/:path*',destination:`${process.env.API_URL || 'http://127.0.0.1:8006'}/api/:path*`}];
  }
};
export default config;
