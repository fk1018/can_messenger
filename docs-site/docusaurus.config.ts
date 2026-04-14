import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'Can Messenger',
  tagline: 'CAN bus messaging for Ruby',
  favicon: 'img/logo.svg',
  url: 'https://can-messenger.github.io',
  baseUrl: '/',
  organizationName: 'can-messenger',
  projectName: 'can-messenger.github.io',
  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'throw',
  i18n: {
    defaultLocale: 'en',
    locales: ['en']
  },
  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: 'docs',
          sidebarPath: './sidebars.ts',
          includeCurrentVersion: true,
          lastVersion: '2.3.0',
          versions: {
            current: {
              label: 'next',
              path: 'next',
              banner: 'unreleased'
            },
            '2.3.0': {
              label: '2.3.0',
              path: ''
            },
            '2.2.0': {
              label: '2.2.0',
              path: '2.2.0'
            },
            '2.1.0': {
              label: '2.1.0',
              path: '2.1.0'
            }
          }
        },
        blog: {
          showReadingTime: true
        },
        theme: {
          customCss: './src/css/custom.css'
        }
      } satisfies Preset.Options
    ]
  ],
  themeConfig: {
    navbar: {
      title: 'Can Messenger',
      logo: {
        alt: 'Can Messenger Logo',
        src: 'img/logo.svg'
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'tutorialSidebar',
          position: 'left',
          label: 'Docs'
        },
        {
          to: '/blog',
          label: 'Blog',
          position: 'left'
        },
        {
          type: 'docsVersionDropdown',
          position: 'right',
          dropdownActiveClassDisabled: true
        },
        {
          href: 'https://rubygems.org/gems/can_messenger',
          label: 'RubyGems',
          position: 'right'
        },
        {
          href: 'https://github.com/fk1018/can_messenger',
          label: 'GitHub',
          position: 'right'
        }
      ]
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {
              label: 'Stable docs',
              to: '/docs'
            },
            {
              label: 'Next docs',
              to: '/docs/next'
            }
          ]
        },
        {
          title: 'Community',
          items: [
            {
              label: 'RubyGems',
              href: 'https://rubygems.org/gems/can_messenger'
            },
            {
              label: 'GitHub',
              href: 'https://github.com/fk1018/can_messenger'
            }
          ]
        }
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Can Messenger`
    }
  } satisfies Preset.ThemeConfig
};

export default config;
