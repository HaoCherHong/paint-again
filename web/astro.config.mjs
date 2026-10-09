// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';
import { SITE_URL } from './src/site.ts';

const ROOT = new URL('/', SITE_URL).href;

export default defineConfig({
  site: SITE_URL,
  output: 'static',
  trailingSlash: 'always',
  integrations: [
    sitemap({
      // `/` only meta-refreshes to /zh-Hant/ (and Cloudflare 302s it). Listing it would
      // put a redirect in <loc> and make two URLs claim hreflang="zh-Hant", which voids
      // the whole annotation group.
      filter: (page) => page !== ROOT,
      i18n: { defaultLocale: 'zh-Hant', locales: { 'zh-Hant': 'zh-Hant', en: 'en' } },
      // Match the <head>: Traditional Chinese is what an unmatched locale gets.
      serialize(item) {
        const zhHant = item.links?.find((link) => link.lang === 'zh-Hant');
        if (zhHant) item.links = [...(item.links ?? []), { lang: 'x-default', url: zhHant.url }];
        return item;
      },
    }),
  ],
  vite: { plugins: [tailwindcss()] },
});
