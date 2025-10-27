/**
 * Creating a sidebar enables you to:
 - create an ordered group of docs
 - render a sidebar for each doc of that group
 - provide next/previous navigation

 The sidebars can be generated from the filesystem, or explicitly defined here.

 Create as many sidebars as you want.
 */

// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  tutorialSidebar: [
    'intro',
    {
      type: 'category',
      label: 'Infrastructure',
      items: [
        'infrastructure/cyclecloud-slurm',
        'infrastructure/aks-cluster',
      ],
    },
    {
      type: 'category',
      label: 'Validations',
      items: [
        {
          type: 'category',
          label: 'AKS',
          items: [
            'validations/aks/storage-performance',
            'validations/aks/nccl-testing',
            'validations/aks/node-health-checks',
          ],
        },
        {
          type: 'category',
          label: 'Slurm',
          items: [
            'validations/slurm/nccl-testing',
            'validations/slurm/node-health-checks',
            'validations/slurm/thermal-testing',
          ],
        },
      ],
    },
    {
      type: 'category',
      label: 'Examples',
      items: [
        {
          type: 'category',
          label: 'AI Training',
          items: [
            'examples/ai-training/megatron-gpt3-slurm',
            'examples/ai-training/megatron-gpt3-aks',
            'examples/ai-training/llm-foundry-slurm',
            'examples/ai-training/llm-foundry-aks',
          ],
        },
        {
          type: 'category',
          label: 'Shared Storage',
          items: [
            'examples/shared-storage/shared-storage-aks',
          ],
        },
      ],
    },
    {
      type: 'category',
      label: 'Guidance',
      items: [
        'guidance/node-labeler',
        'guidance/torset-labeler',
        'guidance/squashed-images',
      ],
    },
  ],
};

module.exports = sidebars;
