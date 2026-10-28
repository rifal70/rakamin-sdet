# Release Notes — AI Interview Platform v1.0.0

## Release Summary
Version `v1.0.0` delivers critical stability, data integrity, and core-flow remediations across the AI Interview Platform. This release establishes the platform's first automated test harnesses, CI/CD quality gate enforcement, and resolves high-severity blockers that previously prevented candidate interview access, broke skill taxonomy linkage, caused unpersisted skill deletions, and dropped live interview coverage signals.

---

## What This Release Delivers

### 1. Core User Journey Unblocking (P0 Fix)
- **Candidate Interview Accessibility (RSK-01):**
  - Resolved candidate invite link generation in `Session#invite_url`.
  - Configured `FRONTEND_URL` environment mapping to port 5173 where the web app serves candidate onboarding and live interview rooms.
  - Added backend redirect route `/interview/:token` -> `http://localhost:5173/interview/:token` on the API server to prevent 404 errors if candidates click port 3001 links directly.

### 2. Data Integrity & Taxonomy Fixes (P1 Fixes)
- **Skill Taxonomy Link Preservation (RSK-03):**
  - Fixed `SkillPicker.tsx` to retain the selected taxonomy `skill_id` instead of hardcoding `skill_id: undefined`.
  - Restored vacancy and assessment alignment with standard taxonomy records, enabling automated Fit/Gap scoring.
- **Nested Skill Deletion Persistence (RSK-04):**
  - Updated `AssessmentsController#update` and `VacanciesController#update` to synchronize deleted child skills with Active Record nested attributes.
  - Omitted skills are now explicitly appended as `{ id: <id>, _destroy: '1' }`, ensuring removed skills are deleted from PostgreSQL rather than orphaned.
- **Coverage Analyzer Skill Mapping (RSK-05):**
  - Enhanced `Coverage::Analyzer#find_map` to symmetrically match both raw string labels and parameterized slugs.
  - Resolved silent dropping of Gemini coverage metadata signals when `skill_id` is omitted.

### 3. Usability & Authentication Improvements (P2 Fixes)
- **Interview Language Configuration in Edit Form (RSK-06):**
  - Added missing Language dropdown (`English` / `Indonesian`) to `AssessmentEditPage.tsx`, ensuring language preferences can be edited and persisted.
- **Assessor Authentication Support (RSK-09):**
  - Broadened `AuthenticationController` verification from `user.role == 'admin'` to `User::ROLES.include?(user.role)`, allowing standard user and assessor accounts to authenticate.
- **API Port Alignment & Candidate Route Interceptor (RSK-10):**
  - Aligned Vite default fallback API and WebSocket URLs from port 3000 to port 3001.
  - Protected candidate `/interview/:token` routes from being prematurely redirected to `/login` on token errors.

---

## Quality System & Automated Checks

This release introduces an automated quality gate architecture:
1. **Pull Request Input Validation (DoR):** Enforces linked specifications, design plans, acceptance criteria, and test references; rejects placeholders (`TODO`, `TBD`).
2. **Backend Regression Suite:** RSpec suites for models, requests, and services (`Session`, `Coverage::Analyzer`, `AssessmentsController`, `FitGap::Engine`).
3. **Frontend Verification:** Contract tests for API client response envelopes, auth routing, and `SkillPicker` payloads, plus TypeScript typecheck and Vite production build.
4. **Automated Release Evaluation:** `.github/workflows/release.yml` executes on tag push and outputs an unambiguous `RELEASABLE` or `BLOCKED` decision summary.

---

## Known Limitations & Remaining Risks

1. **Physical Audio WebSocket Hardware in CI:** Automated CI runs unit, request, and mock-based specs for Gemini Live WebSocket frames. Physical audio card streaming and microphone feedback require manual verification in real browser hardware.
2. **Third-Party AI Service Availability:** Real-time interview generation requires an active Google Gemini API key (`GEMINI_API_KEY`). If the upstream API encounters quota or rate limits, the platform surfaces connection warnings to assessors.

---

## Release Decision
- **Status:** `RELEASABLE`
- **Quality Gate Outcome:** All P0 and P1 blocking defects confirmed and resolved with red-to-green regression coverage.
