import React from 'react';
import clsx from 'clsx';
import styles from './styles.module.css';

const FeatureList = [
  {
    title: '🏗️ Infrastructure References',
    Svg: require('@site/static/img/undraw_docusaurus_mountain.svg').default,
    description: (
      <>
        Deploy and configure Azure infrastructure for AI workloads using Azure CycleCloud 
        with Slurm or Azure Kubernetes Service. Complete guides for GPU-optimized clusters.
      </>
    ),
  },
  {
    title: '🤖 AI Training Examples',
    Svg: require('@site/static/img/undraw_docusaurus_tree.svg').default,
    description: (
      <>
        End-to-end training workflows for large language models including MegatronLM GPT3-175B 
        and LLM Foundry MPT models. Support for both Slurm and Kubernetes orchestration.
      </>
    ),
  },
  {
    title: '✅ Infrastructure Validations',
    Svg: require('@site/static/img/undraw_docusaurus_react.svg').default,
    description: (
      <>
        Test and validate your AI infrastructure with NCCL performance testing, node health 
        checks, thermal testing, and storage performance benchmarks.
      </>
    ),
  },
];

function Feature({Svg, title, description}) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <Svg className={styles.featureSvg} role="img" />
      </div>
      <div className="text--center padding-horiz--md">
        <h3>{title}</h3>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}