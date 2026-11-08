# Auralis

A mobile-first Flutter foundation with an original, in-house design system.

Auralis is intended to be a reusable engineering base for building Android and iOS applications. It is not a demo app, a theme wrapper, or a collection of unrelated UI snippets.

## Direction

- **Platform:** Android and iOS.
- **Framework:** Flutter and Dart.
- **UI foundation:** Flutter SDK primitives, with Auralis-owned components and design tokens.
- **Design system:** Original, consistent, accessible, responsive, and motion-aware.
- **Architecture:** Pragmatic and feature-oriented; complexity must earn its place.

## Non-goals

- Depending on an external UI kit as the visual foundation.
- Requiring a backend, authentication provider, analytics service, or database.
- Adding packages, abstractions, generators, or tooling without a demonstrated need.
- Supporting Flutter web or desktop as project targets.

## Engineering principles

1. Prefer Flutter SDK capabilities before adding dependencies.
2. Keep application-specific decisions out of reusable foundation code.
3. Centralize design tokens; avoid scattered visual magic numbers.
4. Treat accessibility, localization, right-to-left layout, and reduced motion as design requirements.
5. Keep APIs small, explicit, and composable.
6. Verify compatibility and maintenance before adopting third-party packages.
7. Do not add placeholder features or speculative infrastructure.

## Project status

**Foundation setup — in progress.**

The initial repository is intentionally minimal. Platform scaffolding, SDK pinning, dependency selection, architecture, and component APIs will be introduced only after their requirements and compatibility are verified.
