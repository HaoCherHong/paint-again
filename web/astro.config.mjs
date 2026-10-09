// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';
import { SITE_URL } from './src/site.ts';

export default defineConfig({
  site: SITE_URL,
  output: 'static',
  trailingSlash: 'always',
  integrations: [sitemap({ i18n: { defaultLocale: 'zh-Hant', locales: { 'zh-Hant': 'zh-Hant', en: 'en' } } })],
  vite: { plugins: [tailwindcss()] },
});
