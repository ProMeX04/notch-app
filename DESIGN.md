---
name: Cloud Enterprise Precision
colors:
  surface: '#f7f9ff'
  surface-dim: '#d7dae0'
  surface-bright: '#f7f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f1f4fa'
  surface-container: '#ebeef4'
  surface-container-high: '#e5e8ee'
  surface-container-highest: '#dfe3e8'
  on-surface: '#181c20'
  on-surface-variant: '#414754'
  inverse-surface: '#2d3135'
  inverse-on-surface: '#eef1f7'
  outline: '#727785'
  outline-variant: '#c1c6d6'
  surface-tint: '#005bc0'
  primary: '#005bbf'
  on-primary: '#ffffff'
  primary-container: '#1a73e8'
  on-primary-container: '#ffffff'
  inverse-primary: '#adc7ff'
  secondary: '#005ac1'
  on-secondary: '#ffffff'
  secondary-container: '#4d8efe'
  on-secondary-container: '#00285c'
  tertiary: '#006d2c'
  on-tertiary: '#ffffff'
  tertiary-container: '#008939'
  on-tertiary-container: '#ffffff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d8e2ff'
  primary-fixed-dim: '#adc7ff'
  on-primary-fixed: '#001a41'
  on-primary-fixed-variant: '#004493'
  secondary-fixed: '#d8e2ff'
  secondary-fixed-dim: '#adc6ff'
  on-secondary-fixed: '#001a41'
  on-secondary-fixed-variant: '#004494'
  tertiary-fixed: '#89fa9b'
  tertiary-fixed-dim: '#6ddd81'
  on-tertiary-fixed: '#002108'
  on-tertiary-fixed-variant: '#005320'
  background: '#f7f9ff'
  on-background: '#181c20'
  surface-variant: '#dfe3e8'
  google-red: '#EA4335'
  google-yellow: '#FBBC04'
  surface-background: '#F8F9FA'
  border-subtle: '#DADCE0'
  text-primary: '#202124'
  status-info: '#1A73E8'
  status-success: '#1E8E3E'
  status-warning: '#F9AB00'
  status-error: '#D93025'
typography:
  headline-lg:
    fontFamily: hankenGrotesk
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: hankenGrotesk
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  headline-sm:
    fontFamily: hankenGrotesk
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  label-md:
    fontFamily: inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.05em
  code-sm:
    fontFamily: jetbrainsMono
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 18px
  headline-lg-mobile:
    fontFamily: hankenGrotesk
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  base-unit: 4px
  gutter: 16px
  margin-desktop: 24px
  margin-mobile: 16px
  sidebar-width: 256px
  max-content-width: 1440px
---

## Brand & Style

This design system is engineered for professional cloud computing environments where clarity, reliability, and cognitive efficiency are paramount. It reflects a brand personality that is authoritative yet accessible—balancing the immense scale of global infrastructure with the precision of developer tools.

The design style is **Corporate / Modern**, leaning heavily into a refined implementation of Material Design. It prioritizes functional density, systematic hierarchy, and a restrained use of color to ensure that complex data remains the primary focus. The aesthetic is clean and high-fidelity, utilizing a rhythmic grid and intentional whitespace to evoke a sense of limitless scalability and technological innovation.

## Colors

The palette is anchored by the signature Google Blue, used strategically for primary actions and brand recognition. A rigorous "Neutral" spectrum of grays manages the UI's structural integrity, providing clear separation between navigation, surfaces, and content.

- **Primary & Secondary:** Reserved for high-priority interactions, active states, and focus indicators.
- **Semantic Colors:** Green, Yellow, and Red are strictly utilitarian, used for status indicators, health checks, and alerts to ensure immediate visual communication of system states.
- **Surface Strategy:** The UI utilizes a tiered background approach. `#FFFFFF` is used for the primary content canvas, while `#F8F9FA` identifies secondary areas like sidebars, toolbars, or nested containers.

## Typography

The typography system is optimized for legibility and technical precision. By utilizing **Hanken Grotesk** for headlines, we provide a modern, clean, and highly legible alternative to Google Sans that maintains an enterprise feel. **Inter** is the workhorse for body copy, chosen for its exceptional readability in dense data environments.

- **Scale:** A tight typographic scale prevents visual noise.
- **Data Display:** For logs, IDs, and configuration strings, **JetBrains Mono** provides the necessary character distinction required for developer workflows.
- **Hierarchy:** Bold weights are used sparingly, primarily for section headings and primary button labels to guide the user's eye through complex layouts.

## Layout & Spacing

The layout follows a **Fixed Grid** philosophy for dashboard views to ensure consistency across vast amounts of data, transitioning to a more fluid model for documentation and settings pages.

- **Grid Model:** A 12-column grid is standard for desktop. Elements align to a 4px baseline rhythm.
- **Standard Spacing:** Gutters are set at 16px to allow for high information density without sacrificing clarity.
- **Responsive Behavior:** 
  - **Desktop (1280px+):** Fixed side navigation (256px) with a centered or left-aligned content area.
  - **Tablet (768px - 1279px):** Side navigation collapses into an icon rail; margins reduce to 20px.
  - **Mobile (< 767px):** Single column flow; side navigation moves to a drawer; margins reduce to 16px.

## Elevation & Depth

Visual hierarchy is established through **Tonal Layers** and **Low-contrast Outlines** rather than heavy shadows. This keeps the interface feeling "light" and fast.

- **Tier 0 (Background):** `#F8F9FA` for the main application shell.
- **Tier 1 (Surface):** `#FFFFFF` for cards, data tables, and main content blocks. These use a subtle 1px border (`#DADCE0`) instead of a shadow.
- **Tier 2 (Interactive):** Elements that require focus (like active modals or dropdowns) use a soft, ambient shadow: `0 4px 12px rgba(0,0,0,0.08)`.
- **Z-Index:** Navigation sits at the highest level, followed by overlays, then content cards.

## Shapes

The shape language is **Soft (0.25rem)**, reflecting a professional and disciplined structural approach. 

- **Components:** Buttons, input fields, and small chips use the base `rounded` (4px) setting.
- **Containers:** Larger surfaces like cards and modals utilize `rounded-lg` (8px) to provide a gentle visual distinction from the sharper internal elements.
- **Exceptions:** Status "pills" may use a full circular radius to differentiate them from interactive buttons.

## Components

- **Buttons:** Primary buttons use a solid `#1A73E8` fill with white text. Secondary buttons use an outline style with a 1px `#DADCE0` border.
- **Data Tables:** These are the core of the experience. Use a `#FFFFFF` background with 1px horizontal dividers only. Headers should be `label-md` with a subtle `#F8F9FA` fill.
- **Status Indicators:** Use a combination of a colored dot and a text label. Green for 'Active', Yellow for 'Warning', Red for 'Alert', and Blue for 'In Progress'.
- **Input Fields:** Use the "Outlined" Material style. The border turns `#1A73E8` with a 2px stroke on focus.
- **Side Navigation:** A persistent left-hand rail. Active states are indicated by a blue vertical bar on the left edge and a light blue (`#E8F0FE`) background tint for the entire row.
- **Chips:** Small, gray-filled (`#E8EAED`) containers used for tags and metadata, keeping the font size at `body-sm`.