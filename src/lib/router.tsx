import { createContext, useContext, useEffect, useState, useCallback, type ReactNode } from 'react';

interface RouterContextValue {
  path: string;
  navigate: (to: string) => void;
}

const RouterContext = createContext<RouterContextValue | undefined>(undefined);

function getPath(): string {
  const hash = window.location.hash.replace(/^#/, '');
  const path = hash.split('?')[0];
  return path || '/';
}

export function getHashQueryParam(key: string): string | null {
  const hash = window.location.hash.replace(/^#/, '');
  const queryStart = hash.indexOf('?');
  if (queryStart === -1) return null;
  return new URLSearchParams(hash.slice(queryStart + 1)).get(key);
}

export function RouterProvider({ children }: { children: ReactNode }) {
  const [path, setPath] = useState(getPath());

  useEffect(() => {
    const onHashChange = () => setPath(getPath());
    window.addEventListener('hashchange', onHashChange);
    if (!window.location.hash) {
      window.location.hash = '#/';
    }
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);

  const navigate = useCallback((to: string) => {
    window.location.hash = '#' + to;
  }, []);

  return (
    <RouterContext.Provider value={{ path, navigate }}>
      {children}
    </RouterContext.Provider>
  );
}

export function useRouter() {
  const ctx = useContext(RouterContext);
  if (!ctx) throw new Error('useRouter must be used within RouterProvider');
  return ctx;
}

export function Link({ to, children, className, onClick }: { to: string; children: ReactNode; className?: string; onClick?: () => void }) {
  const { navigate } = useRouter();
  return (
    <a
      href={'#' + to}
      className={className}
      onClick={(e) => {
        e.preventDefault();
        if (onClick) onClick();
        navigate(to);
      }}
    >
      {children}
    </a>
  );
}
