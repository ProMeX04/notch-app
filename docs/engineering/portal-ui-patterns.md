# Portal UI Patterns

This standard applies to Next.js pages, React components, and styling in
`portal/`.

## Product Surfaces

- Public product pages should present the real user task first, use a restrained
  hierarchy, and avoid explanatory clutter already implied by the UI.
- `/leaderboard` is the approved baseline for public ranking presentation: clean
  ranked content, polished spacing, restrained metadata, and purposeful motion.
- Admin screens optimize for scanning, comparison, and operational action rather
  than marketing-style composition.

## Components And Data

- Pages render service/API contracts and local view state; they do not reproduce
  auth, ranking, billing, or privacy calculations.
- Reuse layout, type, button, input, icon, and feedback patterns already present
  in the closest comparable surface before introducing new styles.
- Repeated records may be cards or rows; page sections should remain structural
  layouts rather than nested decorative cards.

## Motion, Responsive, And Accessibility

- Use motion to clarify ranking movement, loading, filtering, or navigation.
  Honor `prefers-reduced-motion` and maintain stable geometry while animating.
- Verify narrow and desktop layouts: no text clipping, overlap, or hidden primary
  actions; controls keep usable targets and visible focus state.
- Use semantic HTML, keyboard support, labels, contrast, and meaningful loading,
  empty, error, and disabled states.

## Verification

Run lint/build plus affected tests. For visual changes, inspect desktop and mobile
rendering and browser console behavior before completion.
