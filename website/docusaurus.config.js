// @ts-check
// Note: type annotations allow type checking and IDEs autocompletion

const {themes} = require('prism-react-renderer');
const lightCodeTheme = themes.github;
const darkCodeTheme = themes.dracula;

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'AI Infrastructure on Azure',
  tagline: 'Architectural guidance and training examples for Azure AI Infrastructure',
  favicon: 'img/favicon.ico',

  // Set the production url of your site here
  url: 'https://azure.github.io',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/',

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'Azure', // Usually your GitHub org/user name.
  projectName: 'ai-infrastructure-on-azure', // Usually your repo name.

  onBrokenLinks: 'warn',
  onBrokenMarkdownLinks: 'warn',

  // Even if you don't use internalization, you can use this field to set useful
  // metadata like html lang. For example, if your site is Chinese, you may want
  // to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          sidebarPath: require.resolve('./sidebars.js'),
          editUrl: 'https://github.com/Azure/ai-infrastructure-on-azure/tree/main/docusaurus/',
        },
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      // Replace with your project's social card
      image: 'img/docusaurus-social-card.jpg',
      navbar: {
        title: 'AI Infrastructure on Azure',
        logo: {
          alt: 'Azure Logo',
          src: 'img/logo.svg',
        },
        items: [
          {
            to: '/docs/infrastructure/cyclecloud-slurm',
            label: 'Infrastructure',
            position: 'left',
          },
          {
            to: '/docs/validations/aks/storage-performance',
            label: 'Validations',
            position: 'left',
          },
          {
            to: '/docs/examples/ai-training/megatron-gpt3-slurm',
            label: 'Examples',
            position: 'left',
          },
          {
            to: '/docs/guidance/node-labeler',
            label: 'Guidance',
            position: 'left',
          },
          {
            href: 'https://github.com/Azure/ai-infrastructure-on-azure',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Documentation',
            items: [
              {
                label: 'Infrastructure',
                to: '/docs/infrastructure/cyclecloud-slurm',
              },
              {
                label: 'AI Training Examples',
                to: '/docs/examples/ai-training/megatron-gpt3-slurm',
              },
              {
                label: 'Validations',
                to: '/docs/validations/aks/nccl-testing',
              },
              {
                label: 'Guidance',
                to: '/docs/guidance/node-labeler',
              },
            ],
          },
          {
            title: 'Azure Services',
            items: [
              {
                label: 'Azure Kubernetes Service',
                href: 'https://learn.microsoft.com/en-us/azure/aks/what-is-aks',
              },
              {
                label: 'Azure CycleCloud',
                href: 'https://learn.microsoft.com/en-us/azure/cyclecloud/overview-ccws?view=cyclecloud-8',
              },
              {
                label: 'Azure Machine Learning',
                href: 'https://learn.microsoft.com/en-us/azure/machine-learning/?view=azureml-api-2',
              },
            ],
          },
          {
            title: 'More',
            items: [
              {
                label: 'GitHub',
                href: 'https://github.com/Azure/ai-infrastructure-on-azure',
              },
              {
                label: 'Microsoft Learn',
                href: 'https://learn.microsoft.com/',
              },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} Microsoft Corporation. Built with Docusaurus.`,
      },
      prism: {
      theme: lightCodeTheme,
      darkTheme: darkCodeTheme,
      additionalLanguages: ['powershell', 'bash', 'yaml', 'json'],
    },
      // Algolia search configuration (uncomment and configure when ready)
      // algolia: {
      //   appId: 'YOUR_APP_ID',
      //   apiKey: 'YOUR_SEARCH_API_KEY',
      //   indexName: 'YOUR_INDEX_NAME',
      //   contextualSearch: true,
      // },
    }),
};

module.exports = config;