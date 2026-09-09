import React from 'react';
import { Hero } from '../components/Hero';
import { PosSimulator } from '../components/PosSimulator';
import { FeaturePillars } from '../components/FeaturePillars';
import { FloorManagement } from '../components/FloorManagement';
import { PlayStoreBanner } from '../components/PlayStoreBanner';
import { Pricing } from '../components/Pricing';
import { Testimonials } from '../components/Testimonials';
import { FAQ } from '../components/FAQ';

interface HomePageProps {
  onOpenDemo: (plan?: string) => void;
}

export const HomePage: React.FC<HomePageProps> = ({ onOpenDemo }) => {
  const scrollToSimulator = () => {
    const el = document.getElementById('simulator');
    if (el) {
      el.scrollIntoView({ behavior: 'smooth' });
    }
  };

  return (
    <main>
      <Hero onOpenDemo={() => onOpenDemo()} onScrollToSimulator={scrollToSimulator} />
      <PosSimulator />
      <FeaturePillars />
      <FloorManagement />
      <PlayStoreBanner />
      <Pricing onOpenDemo={onOpenDemo} />
      <Testimonials />
      <FAQ />
    </main>
  );
};
