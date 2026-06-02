/// <reference types="vite/client" />

import * as React from 'react'

declare global {
  namespace JSX {
    interface IntrinsicElements {
      'lottie-player': React.DetailedHTMLProps<React.HTMLAttributes<HTMLElement>, HTMLElement> & {
        src?: string;
        background?: string;
        speed?: string;
        loop?: boolean;
        autoplay?: boolean;
        controls?: boolean;
        style?: React.CSSProperties;
      };
    }
  }

  namespace React {
    namespace JSX {
      interface IntrinsicElements {
        'lottie-player': React.DetailedHTMLProps<React.HTMLAttributes<HTMLElement>, HTMLElement> & {
          src?: string;
          background?: string;
          speed?: string;
          loop?: boolean;
          autoplay?: boolean;
          controls?: boolean;
          style?: React.CSSProperties;
        };
      }
    }
  }
}

declare module 'react' {
  namespace JSX {
    interface IntrinsicElements {
      'lottie-player': React.DetailedHTMLProps<React.HTMLAttributes<HTMLElement>, HTMLElement> & {
        src?: string;
        background?: string;
        speed?: string;
        loop?: boolean;
        autoplay?: boolean;
        controls?: boolean;
        style?: React.CSSProperties;
      };
    }
  }
}
