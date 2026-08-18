/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    screens: {
      xs: '400px',
      sm: '640px',
      md: '768px',
      lg: '1024px',
      xl: '1280px',
      '2xl': '1536px',
    },
    extend: {
      colors: {
        ink: {
          950: '#000000',
          900: '#0a0a0c',
          850: '#0f0f12',
          800: '#141417',
          750: '#1a1a1e',
          700: '#1f1f24',
          600: '#2a2a30',
          500: '#3a3a42',
          400: '#52525b',
        },
        brand: {
          50: '#f1effe',
          100: '#e4e0fc',
          200: '#c9c2f8',
          300: '#a99cf2',
          400: '#8b7ce9',
          500: '#673de6',
          600: '#5a2dc7',
          700: '#4a24a3',
          800: '#3b1d80',
          900: '#2b1659',
        },
        success: { 500: '#22c55e', 600: '#16a34a', 700: '#15803d' },
        warning: { 500: '#f59e0b', 600: '#d97706' },
        danger: { 500: '#ef4444', 600: '#dc2626', 700: '#b91c1c' },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'ui-monospace', 'monospace'],
      },
      animation: {
        'fade-in': 'fadeIn 0.3s ease-out',
        'slide-up': 'slideUp 0.4s ease-out',
        'pulse-brand': 'pulseBrand 2s ease-in-out infinite',
      },
      keyframes: {
        fadeIn: { '0%': { opacity: '0' }, '100%': { opacity: '1' } },
        slideUp: {
          '0%': { opacity: '0', transform: 'translateY(12px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        pulseBrand: {
          '0%, 100%': { boxShadow: '0 0 0 0 rgba(103,61,230,0.4)' },
          '50%': { boxShadow: '0 0 0 8px rgba(103,61,230,0)' },
        },
      },
    },
  },
  plugins: [],
};
