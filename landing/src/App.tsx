import React, { useState } from 'react';
import { useRouter } from './router';
import { Navbar } from './components/Navbar';
import { Footer } from './components/Footer';
import { DemoModal } from './components/DemoModal';
import { ConsoleApp } from './console/console';
import { HomePage } from './pages/HomePage';
import { PrivacyPolicyPage } from './pages/PrivacyPolicyPage';
import { DataDeletionPage } from './pages/DataDeletionPage';
import { TermsPage } from './pages/TermsPage';
import { RefundPolicyPage } from './pages/RefundPolicyPage';

export const App: React.FC = () => {
  const { currentPath } = useRouter();
  const [isDemoOpen, setIsDemoOpen] = useState(false);
  const [selectedPlan, setSelectedPlan] = useState<string | undefined>();

  const handleOpenDemo = (plan?: string) => {
    setSelectedPlan(plan);
    setIsDemoOpen(true);
  };

  // Owner & superadmin console: rendered standalone (no marketing chrome).
  if (currentPath.startsWith('/console')) {
    return <ConsoleApp />;
  }

  const renderRoute = () => {
    switch (currentPath) {
      case '/privacy-policy':
        return <PrivacyPolicyPage />;
      case '/data-deletion':
        return <DataDeletionPage />;
      case '/terms':
        return <TermsPage />;
      case '/refund-policy':
        return <RefundPolicyPage />;
      case '/':
      default:
        return <HomePage onOpenDemo={handleOpenDemo} />;
    }
  };

  return (
    <div className="page-full-width">
      <Navbar onOpenDemo={() => handleOpenDemo()} />
      {renderRoute()}
      <Footer />
      <DemoModal
        isOpen={isDemoOpen}
        onClose={() => setIsDemoOpen(false)}
        defaultPlan={selectedPlan}
      />
    </div>
  );
};
