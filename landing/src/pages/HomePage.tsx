import React from 'react';
import { TemplateHero } from '../components/TemplateHero';
import { FeaturesGrid } from '../components/FeaturesGrid';
import { BenefitsSection } from '../components/BenefitsSection';
import { PlayStoreBanner } from '../components/PlayStoreBanner';
import { Pricing } from '../components/Pricing';
import { FAQ } from '../components/FAQ';

interface HomePageProps {
  onOpenDemo: (plan?: string) => void;
}

export const HomePage: React.FC<HomePageProps> = ({ onOpenDemo }) => {
  return (
    <main>
      <TemplateHero onOpenDemo={() => onOpenDemo()} />
      <FeaturesGrid />
      <BenefitsSection />
      <PlayStoreBanner onOpenDemo={() => onOpenDemo()} />
      <Pricing />
      <FAQ />
    </main>
  );
};
