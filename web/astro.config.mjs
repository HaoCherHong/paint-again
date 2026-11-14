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
      // `/` only redirects (client-side, by browser language). Listing it would put a
      // redirect in <loc> and, since the i18n option reads an unprefixed URL as the default
      // locale, make two URLs claim hreflang="zh-Hant", which voids the whole annotation group.
      filter: (page) => page !== ROOT,
      i18n: { defaultLocale: 'zh-Hant', locales: { 'zh-Hant': 'zh-Hant', en: 'en' } },
      // Match the <head>: English is what an unmatched locale gets.
      serialize(item) {
        const en = item.links?.find((link) => link.lang === 'en');
        if (en) item.links = [...(item.links ?? []), { lang: 'x-default', url: en.url }];
        return item;
      },
    }),
  ],
  vite: { plugins: [tailwindcss()] },
});
