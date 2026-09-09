import React, { createContext, useContext, useState, useEffect } from 'react';

export type RoutePath =
  | '/'
  | '/privacy-policy'
  | '/terms'
  | '/data-deletion'
  | '/refund-policy';

interface RouterContextType {
  currentPath: string;
  navigate: (path: RoutePath | string) => void;
}

const RouterContext = createContext<RouterContextType>({
  currentPath: '/',
  navigate: () => {},
});

export const RouterProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const getCleanPath = (): string => {
    // Check hash first (e.g. #/privacy-policy or #privacy-policy) for static hosting compatibility
    const hash = window.location.hash.replace(/^#\/?/, '/');
    if (hash && hash !== '/') {
      return hash.startsWith('/') ? hash : `/${hash}`;
    }
    const path = window.location.pathname;
    return path || '/';
  };

  const [currentPath, setCurrentPath] = useState<string>(getCleanPath());

  useEffect(() => {
    const handlePopState = () => {
      setCurrentPath(getCleanPath());
    };

    window.addEventListener('popstate', handlePopState);
    window.addEventListener('hashchange', handlePopState);
    return () => {
      window.removeEventListener('popstate', handlePopState);
      window.removeEventListener('hashchange', handlePopState);
    };
  }, []);

  const navigate = (path: RoutePath | string) => {
    try {
      window.history.pushState({}, '', path);
    } catch {
      window.location.hash = path;
    }
    setCurrentPath(path);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  return (
    <RouterContext.Provider value={{ currentPath, navigate }}>
      {children}
    </RouterContext.Provider>
  );
};

export const useRouter = () => useContext(RouterContext);
