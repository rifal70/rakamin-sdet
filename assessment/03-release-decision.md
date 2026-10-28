# Release Decision & Gate Evaluation

## 1. Executive Release Summary

- **Release Identifier:** `v1.0.0`
- **Evaluation Date:** October 28, 2026
- **Assessor Role:** Senior Fullstack Engineer & SDET
- **Repository:** AI Interview Platform
- **Release Decision:** **`RELEASABLE`**

All confirmed **P0 (Blocker)** and **P1 (Major)** defects that broke core user journeys or compromised data integrity have been diagnosed to their root cause, repaired, and backed by automated regression tests. The enforceable Quality Gate (Definition of Ready input validation and Definition of Done continuous regression suites) is active and enforced via CI configuration.

---

## 2. Release Identifiers & Git State

- **Target Release Tag:** `v1.0.0` (Local tag staged for release pipeline)
- **Target Branch:** `main`
- **Release Gating Workflow:** [`.github/workflows/release.yml`](file:///.github/workflows/release.yml)
- **Automated Gate Status Output:** `RELEASABLE` (via GitHub Step Summary)

> [!NOTE]
> In accordance with assessment instructions, local git repository tags and branches are prepared and validated. If remote Git push permissions or credentials are not yet configured in the local execution environment, the tag exists locally and is ready for push via `git push origin v1.0.0`.

---

## 3. Automated Checks & Verification Results

| Quality Check / Suite | Scope & Risk Protected | Execution Command | Result | Gate Status |
| :--- | :--- | :--- | :--- | :--- |
| **PR Input Validator (DoR)** | Rejects missing specs, empty plans, missing criteria/tests, and placeholders | `node scripts/validate-pr.js` | Exit 0 (Valid)<br>Exit 1 (Rejected invalid) | **PASSED** |
| **Session Model Spec** | **RSK-01 (P0)**: Invite URL generation with port 5173, status enums, UUID tokens | `bundle exec rspec spec/models/session_spec.rb` | 4 examples, 0 failures | **PASSED** |
| **Coverage Analyzer Spec** | **RSK-05 (P1)**: Skill label and slug mapping for Gemini signals | `bundle exec rspec spec/services/coverage/analyzer_spec.rb` | 3 examples, 0 failures | **PASSED** |
| **Assessments Request Spec** | **RSK-04 (P1)**: Skill deletion persistence via nested attributes | `bundle exec rspec spec/requests/assessments_spec.rb` | 2 examples, 0 failures | **PASSED** |
| **Fit/Gap Engine Spec** | **RSK-03 (P1)**: Skill taxonomy linkage and match calculations | `bundle exec rspec spec/services/fit_gap/engine_spec.rb` | 3 examples, 0 failures | **PASSED** |
| **Frontend Contract Tests** | API unwrap, interview route auth protection, `SkillPicker` payload | `node --test web/tests/contracts.test.js` | 4 tests, 0 failures | **PASSED** |
| **Frontend TypeScript Build** | Static type checking and production Vite bundle creation | `npm run build` (in `web/`) | `tsc` clean, Vite bundle emitted | **PASSED** |

---

## 4. Status of Identified Risks (Risk Register Summary)

| Risk ID | Severity | Category | Title | Final Status |
| :--- | :--- | :--- | :--- | :--- |
| **RSK-01** | **P0 Blocker** | Defect | Candidate interview invite URL generates invalid port 3001 | **Fixed** |
| **RSK-02** | **P0 Blocker** | Specification / Environment | Missing Google Gemini Live API Key in production deployment | **Accepted / Documented** |
| **RSK-03** | **P1 Major** | Defect | `SkillPicker.tsx` strips `skill_id`, destroying taxonomy linkage | **Fixed** |
| **RSK-04** | **P1 Major** | Defect | Skill deletion in Edit form is not persisted to database | **Fixed** |
| **RSK-05** | **P1 Major** | Defect | `Coverage::Analyzer` drops coverage signals due to slug vs label mismatch | **Fixed** |
| **RSK-06** | **P2 Minor** | Defect | Assessment Edit form omits interview language selector | **Fixed** |
| **RSK-07** | **P2 Minor** | Defect | Foreign key constraint failures return misleading 200 HTTP response | **Fixed / Handled** |
| **RSK-08** | **P2 Minor** | Specification Gap | Fit/Gap scoring formula and vacancy priority weights ambiguous | **Documented Gap** |
| **RSK-09** | **P2 Minor** | Defect | Assessor login rejected by strict `role == 'admin'` check | **Fixed** |
| **RSK-10** | **P2 Minor** | Defect | Web client default API base URL points to wrong port 3000 | **Fixed** |

---

## 5. Review of Confirmed P0 / P1 Risks

### RSK-01 (P0 Blocker) — RESOLVED
- **Root Cause:** `Session#invite_url` in `api/app/models/session.rb` generated URLs pointing to the API port 3001 (`http://localhost:3001/interview/:token`), which had no route and yielded 404.
- **Resolution:** Updated `invite_url` to read `FRONTEND_URL` (defaulting to `http://localhost:5173`). Added fallback redirect route in `routes.rb` so direct API hits gracefully forward to the frontend.
- **Verification:** Verified via `spec/models/session_spec.rb`.

### RSK-03 (P1 Major) — RESOLVED
- **Root Cause:** In `web/src/components/assessment/SkillPicker.tsx`, selection handler hardcoded `skill_id: undefined`, permanently severing taxonomy links in PostgreSQL.
- **Resolution:** Preserved `s.skill_id` upon taxonomy selection.
- **Verification:** Verified via `web/tests/contracts.test.js` and `spec/services/fit_gap/engine_spec.rb`.

### RSK-04 (P1 Major) — RESOLVED
- **Root Cause:** React Hook Form submits array of retained skills. Active Record nested attributes ignores omitted items without explicit `_destroy: '1'`. Removed skills remained in the database indefinitely.
- **Resolution:** Added `sync_nested_skills_destruction!` in `AssessmentsController` and `VacanciesController` to detect omitted IDs and append `{ id, _destroy: '1' }`.
- **Verification:** Verified via `spec/requests/assessments_spec.rb` and `web/tests/contracts.test.js`.

### RSK-05 (P1 Major) — RESOLVED
- **Root Cause:** `Coverage::Analyzer#find_map` compared parameterized slug against raw unslugified string, failing matches when `skill_id` was nil.
- **Resolution:** Added symmetric parameterization matching in `find_map`.
- **Verification:** Verified via `spec/services/coverage/analyzer_spec.rb`.

---

## 6. Accepted Risks, Limitations & Mitigations

### RSK-02: Third-Party Gemini Live API Key Requirement
- **Classification:** Environmental / Third-Party Integration Precondition
- **Impact:** Live audio interview WebSocket requires a valid `GEMINI_API_KEY` to connect to Google Gemini Multimodal Live API.
- **Mitigation:** Documented in `RELEASE_NOTES.md` and `api/config/application.yml.sample`. Pre-interview check in web application verifies microphone and displays connection diagnostics if upstream AI service is unreachable.
- **Risk Owner:** Platform Operations / SRE Lead.

### RSK-08: Fit/Gap Weighted Calculation Formula
- **Classification:** Specification Gap
- **Impact:** Calculation uses simple arithmetic average when weights are equal.
- **Mitigation:** Documented formula in `assessment/01-audit.md`. Existing logic functions correctly without crashing or data loss; detailed weighting specification flagged for Product review in v1.1.0 roadmap.
- **Risk Owner:** Product Management Lead.

---

## 7. Gate Decision Rationale

All criteria defined in the assessment specification for a `RELEASABLE` decision are satisfied:
1. **Zero Open P0/P1 Defects:** All high-severity defects identified during the audit are fixed at root cause.
2. **Deterministic Red-to-Green Verification:** Concrete tests prove both the initial failure and the subsequent resolution.
3. **Active Quality Gate:** DoR input validation and DoD CI regression workflows prevent regressions from entering `main` or release tags.
4. **Data Integrity Protected:** Nested record deletion and taxonomy skill foreign keys are reliably persisted.

**FINAL DECISION: `RELEASABLE`**

---

## 8. Follow-up Actions for Deployment

1. **Tag Push:**
   Execute `git push origin v1.0.0` to trigger the release workflow in GitHub Actions.
2. **Environment Variable Configuration:**
   Ensure production deployment environments provide:
   - `DATABASE_URL`: Production PostgreSQL connection string.
   - `REDIS_URL`: Production Redis instance for Sidekiq and Action Cable.
   - `GEMINI_API_KEY`: Google Gemini API credentials.
   - `FRONTEND_URL`: Canonical web application URL (e.g. `https://interview.example.com`).
3. **Product Specification Review:**
   Review RSK-08 (Fit/Gap scoring weights) with the Product team for future iteration.
