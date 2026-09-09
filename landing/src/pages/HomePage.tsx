import React from 'react';
import { TemplateHero } from '../components/TemplateHero';
import { FeaturesGrid } from '../components/FeaturesGrid';
import { BenefitsSection } from '../components/BenefitsSection';
import { PlayStoreBanner } from '../components/PlayStoreBanner';
import { Pricing } from '../components/Pricing';
import { Testimonials } from '../components/Testimonials';
import { FAQ } from '../components/FAQ';

interface HomePageProps {
  onOpenDemo: (plan?: string) => void;
}

export const HomePage: React.FC<HomePageProps> = ({ onOpenDemo }) => {
  const scrollTo = (targetId: string) => () => {
    const el = document.getElementById(targetId);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth' });
    }
  };

  return (
    <main>
      <TemplateHero onOpenDemo={() => onOpenDemo()} onScrollToFeatures={scrollTo('features')} />
      <FeaturesGrid />
      <BenefitsSection />
      <PlayStoreBanner />
      <Pricing onOpenDemo={onOpenDemo} />
      <Testimonials />
      <FAQ />
    </main>
  );
};
