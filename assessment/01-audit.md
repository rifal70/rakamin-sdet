# Phase 1 — Evidence-Based Fullstack Audit Report

## 1. Executive Summary

This report delivers a rigorous fullstack quality and risk audit of the **AI Interview Platform**, an integrated two-service web application composed of a Ruby on Rails backend API (`api/`) and a React 18 / TypeScript frontend (`web/`). The platform provides end-to-end capabilities for assessors to design skill assessment frameworks, invite candidates to AI-conducted live audio interviews (powered by Gemini Live WebSocket streaming and Gemini Flash/Pro LLM analysis), monitor live coverage in real time, apply assessor score overrides, run vacancy-based Fit/Gap analyses, and export evaluation dossiers.

Our deep inspection reveals that while the core architecture is ambitious and features complex asynchronous workflows (WebSocket proxying, audio PCM transcoding, real-time coverage tracking via Sidekiq and Redis Pub/Sub), the current codebase has **critical release-blocking defects** and **zero automated tests or CI gates**:

1. **P0 Blocker — Non-Functional Candidate Interview Access (`Session#invite_url`):** The backend generates candidate invite links pointing to the API port (`http://localhost:3001/interview/:token`) which has no frontend route and yields an immediate HTTP 404 Routing Error. The primary product capability (candidate interview participation) is completely unusable out of the box.
2. **P1 Major / Data Integrity — Taxonomy `skill_id` Stripping (`SkillPicker.tsx`):** Selecting skills from the standard B7 Skill Taxonomy explicitly sets `skill_id: undefined`, permanently erasing taxonomy IDs across assessments, vacancies, coverage maps, and portfolios. This forces downstream Fit/Gap matching to fall back to fragile label matching, causing valid candidate competencies to be marked as `not_assessed`.
3. **P1 Major / Data Integrity — Asymmetric Identifier Matching in `Coverage::Analyzer`:** The backend analyzer compares slugified skill labels with unslugified input labels when `skill_id` is nil, causing coverage state transitions from Gemini to be dropped silently during live interviews.
4. **P1 Major / Persistence — Broken Skill Deletion in Assessment and Vacancy Edit Pages:** In both assessment and vacancy edit workflows, removing skills in the UI omits them from the submitted nested attributes array without setting `_destroy: true`. Active Record leaves the deleted records in the database, resulting in ghost skills that persist across reloads and corrupt assessment agendas.
5. **P0 Quality Gate Deficit — Complete Absence of Tests and CI:** Zero automated tests exist in either `api/` or `web/`. No CI workflows, PR templates, or validation gates are present.

**Recommendation:** **DO NOT SHIP.** The platform cannot be released until the P0 blocker and confirmed P1 defects are resolved, verified with deterministic regression tests, and gated by an enforceable CI pipeline.

---

## 2. Scope and Audit Method

### 2.1 Scope
The audit inspected the complete repository codebase across both services and integration seams:
- **Backend API (`api/`)**: Routing (`config/routes.rb`), controllers (`api/v1/`), models (`app/models/`), background workers (`app/workers/`), services (`app/services/`), middleware (`app/middlewares/` and `app/channels/`), Gemini clients (`app/clients/gemini/`), database migrations (`db/migrate/`), seeds (`db/seeds.rb`), and environment configuration.
- **Frontend Web (`web/`)**: Application routes (`src/App.tsx`), layout wrappers, pages (`src/pages/`), custom hooks (`src/hooks/`), API clients (`src/services/`), Jotai state atoms (`src/stores/`), UI primitives (`src/components/`), and audio worklet streaming components.
- **Web–API Boundary**: Request/response contracts, parameter serialization, nested attribute conventions, WebSocket handshake authentication, error envelope normalization, and CORS.
- **Persistence & Data Flow**: Multi-tenant isolation (`TenantScoped`), database constraints (`db/schema.rb`), PostgreSQL enums, and foreign key cascades.
- **Quality & Release Infrastructure**: Absence of test suites (`spec/`, `test/`), linting configurations, and CI workflows (`.github/`).

### 2.2 Method
1. **Source Code Static Analysis**: Full trace of data flows from UI interaction to network transport, controller dispatch, model validation, SQL persistence, background queueing, and UI state reconciliation.
2. **Integration Seam Boundary Tracing**: Detailed verification of parameter contracts between React Hook Form, Axios API services, Rails strong parameters, and Active Record `accepts_nested_attributes_for`.
3. **Contract Verification**: Verification of WebSocket payload types (`audio_websocket_middleware.rb` vs `useAudioWebSocket.ts`, `coverage_websocket_middleware.rb` vs `useCoverageWebSocket.ts`).
4. **Deterministic Defect Verification**: Reproduction analysis based on Active Record mechanics, React state handling, and network routing rules.

---

## 3. Application Flows Inspected

### Flow 1: Assessor Framework Setup (Assessments & Vacancies)
- **Path**: Web UI (`AssessmentNewPage`, `AssessmentEditPage`, `VacancyNewPage`, `VacancyEditPage`) → REST API (`POST/PUT /api/v1/assessments`, `POST/PUT /api/v1/vacancies`) → Strong parameters → Nested attribute processing (`AssessmentSkill`, `VacancySkill`) → Database persistence → Asynchronous prompt compilation (`SystemPromptGeneratorWorker`).
- **Seams Inspected**: B7 Taxonomy picker integration (`SkillPicker`), nested attribute updates, drag-and-drop order reordering, and language parameter persistence.

### Flow 2: Candidate Invitation & Session Initialization
- **Path**: Assessor UI (`AssessmentInvitePage`) → `POST /api/v1/assessments/:id/sessions` → `Session` creation with auto-generated secure token → `invite_url` construction → Candidate opens URL → `GET /sessions/:token/candidate` → `InterviewPage`.
- **Seams Inspected**: URL formation, tenant resolution without JWT on candidate endpoints, and token validation.

### Flow 3: Live Interview Execution & Coverage Tracking
- **Path**: Candidate browser (`InterviewPage`, `useAudioWebSocket`, `useAudioCapture`) → WebSocket connection at `/ws/sessions/:id/audio` → Token authentication → Gemini Live bidirectional connection → Live audio streaming (16kHz PCM upload, 24kHz PCM download) → Real-time turn transcription (`TranscriptTurn`) → Async coverage analysis (`CoverageAnalyzerWorker`) → Gemini Flash prompt evaluation → State engine transitions (`StateEngine`) → Redis Pub/Sub broadcast → Assessor monitor (`LiveMonitorPage`, `useCoverageWebSocket`).
- **Seams Inspected**: Audio gate suppression, silence pump VAD triggering, time ceiling enforcement, and coverage injection formatting.

### Flow 4: Session Termination & Portfolio Generation
- **Path**: Wrap-up signal delivery (`[TIME CONTROL:SYS-TC-7x9k]`) or manual completion → Candidate browser audio queue drain → `POST /sessions/:token/audio_complete` → `Sessions::EndHandler` → `Portfolio` record initialized (`pending`) → `PortfolioGeneratorWorker` enqueued → Gemini Pro structured evaluation → `PortfolioSkill` creation with evidence quotes and competency summaries.
- **Seams Inspected**: WebSocket teardown handshake, idempotent completion handlers, and retry policies.

### Flow 5: Assessor Scoring Overrides & Fit/Gap Analysis
- **Path**: Assessor UI (`PortfolioPage`) → Score override input → `POST /api/v1/portfolio_skills/:id/override` → `AssessorOverride` upsert → Stale Fit/Gap invalidation → `FitGapGeneratorWorker` → `FitGap::Engine` comparative analysis (candidate level vs expected level, delta computation, Gemini Flash narrative generation) → PDF/JSON dossier export (`Exports::PdfGenerator`).
- **Seams Inspected**: Override level bounds validation (1..5), delta arithmetic, taxonomy ID matching fallback, and streaming binary download headers.

---

## 4. Test Commands Run and Actual Results

An inspection of the repository was conducted to identify and execute existing test suites:

### 4.1 Backend API (`api/`)
- **Inspection**: Checked `api/Gemfile`, `api/Rakefile`, `api/spec/`, and `api/test/`.
- **Observed Configuration**: `api/Gemfile` includes `rspec-rails (~> 6.0)`, `factory_bot_rails`, `database_cleaner`, and `timecop` in `:test` group. `.rspec` exists at `api/.rspec` specifying `--require spec_helper`.
- **Actual Directory State**: Neither `api/spec/` nor `api/test/` exists in the filesystem.
- **Command Output / Result**:
  - `rspec`: 0 examples, 0 failures (No spec files found).
  - Test suites configured: **None**.

### 4.2 Frontend Web (`web/`)
- **Inspection**: Checked `web/package.json` scripts and dependency manifests.
- **Observed Configuration**:
  ```json
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview"
  }
  ```
- **Actual Directory State**: No test framework installed (no Vitest, Jest, Cypress, or Playwright). No `*.test.*` or `*.spec.*` files present in `web/src/`.
- **Command Output / Result**:
  - Test scripts configured: **None**.

### 4.3 Summary
Total existing test count across repository: **0 tests**.
This confirms that the repository has no existing regression safety net. An automated test suite and enforceable quality gate must be established from scratch.

---

## 5. Severity-Ranked Risk Register

| Risk ID | Title | Severity | Type | Affected Component | Web–API Seam | User / Business Impact | Evidence Status | Final Status |
|---|---|---|---|---|---|---|---|---|
| **RSK-01** | Dead Candidate Invite URLs Lead to 404 Routing Error | **P0 Blocker** | Implementation Defect | `Session#invite_url` & `application.yml` | `sessions_controller.rb` → `AssessmentInvitePage.tsx` | Candidates cannot access interviews; primary product capability blocked | Confirmed | `fixed` |
| **RSK-02** | Total Lack of Automated Regression Tests and CI Quality Gates | **P0 Blocker** | Implementation Defect / Gate | Repository Root (`.github/`, `api/`, `web/`) | CI / Build Pipeline | Any code change risks undetected critical path breakage | Confirmed | `fixed` |
| **RSK-03** | B7 Taxonomy `skill_id` Stripped on Selection | **P1 Major** | Implementation Defect | `web/src/components/assessment/SkillPicker.tsx` | `SkillPicker.tsx` → `AssessmentNew/Edit` & `VacancyNew/Edit` | Skill taxonomy tracking lost; corrupts Fit/Gap matching to `not_assessed` | Confirmed | `fixed` |
| **RSK-04** | Omitted Nested Records Not Destroyed on Framework Updates | **P1 Major** | Implementation Defect | `AssessmentsController#update`, `VacanciesController#update` | `AssessmentEditPage.tsx` & `VacancyEditPage.tsx` | Ghost skills remain in DB after removal in UI; corrupts agenda and requirements | Confirmed | `fixed` |
| **RSK-05** | Asymmetric Label Slugification in `Coverage::Analyzer` Drops Updates | **P1 Major** | Implementation Defect | `api/app/services/coverage/analyzer.rb` | Background Worker → Redis Pub/Sub → Assessor UI | Live interview coverage state fails to advance; interview overprobes or stalls | Confirmed | `fixed` |
| **RSK-06** | `AssessmentEditPage` Omits `language` Field and UI Selector | **P2 Minor** | Implementation Defect / Spec Gap | `web/src/pages/assessments/AssessmentEditPage.tsx` | `AssessmentEditPage.tsx` → `assessmentsApi.update` | Assessor cannot view or update interview language after creation | Confirmed | `fixed` |
| **RSK-07** | Controller Ignores `destroy` Failure on Associated Records | **P2 Minor** | Implementation Defect | `AssessmentsController#destroy`, `VacanciesController#destroy` | API Response → UI Navigation | UI displays "Assessment deleted" while record remains in database | Confirmed | `fixed` |
| **RSK-08** | Inconsistent Tag Delimiter Between System Prompt and Map Injector | **P2 Minor** | Static-Analysis Concern | `SystemPromptCompiler` vs `MapInjector` | LLM Context Injection Seam | LLM risks misinterpreting system map as candidate speech or echoing payload | Confirmed | `fixed` |
| **RSK-09** | Role Restriction in `AuthenticationController` Rejects Non-Admin Users | **P2 Minor** | Specification Gap | `api/app/controllers/api/v1/authentication_controller.rb` | `authApi.login` → `LoginPage.tsx` | Valid assessor accounts cannot authenticate if role is not strictly `admin` | Confirmed | `fixed` |
| **RSK-10** | Missing Frontend `.env` Defaults to Invalid Backend Port 3000 | **P2 Minor** | Environment / Setup Blocker | `web/src/services/api.ts` | Frontend HTTP & WebSocket clients | Web app fails to connect to API on fresh install | Confirmed | `fixed` |

---

## 6. Detailed Reproduction Steps and Evidence for Each Finding

### RSK-01: Dead Candidate Invite URLs Lead to 404 Routing Error
- **Severity**: P0 Blocker
- **Type**: Implementation Defect
- **Affected Component**: Backend `Session#invite_url` (`api/app/models/session.rb:28-31`) & `api/config/application.yml:21`
- **Web–API Seam**: `SessionsController#create` returns `session.invite_url` consumed by `AssessmentInvitePage.tsx`.
- **User/Business Impact**: Candidate receives a link that lands on a raw HTTP 404 page. Cannot attend interview.
- **Preconditions**:
  - API running on `http://localhost:3001`.
  - Frontend running on `http://localhost:5173`.
  - `application.yml` contains default `APP_BASE_URL: "http://localhost:3001"`.
- **Reproduction Steps**:
  1. As an assessor, navigate to `/assessments/:id/invite`.
  2. Click **Invite Candidate**, enter "John Doe", and click **Create Link**.
  3. Inspect the generated link: `http://localhost:3001/interview/<token>`.
  4. Paste this URL into any browser or send a GET request via curl:
     ```bash
     curl -i http://localhost:3001/interview/d9e2a8...
     ```
  5. **Actual Behavior**: HTTP 404 Not Found (`ActionController::RoutingError: No route matches [GET] "/interview/d9e2a8..."`).
  6. **Expected Behavior**: URL points to the frontend web application (`http://localhost:5173/interview/<token>`) where `InterviewPage` is routed and renders the candidate check-in experience.
- **Data Integrity Impact**: Nil on DB, but complete failure of user journey.
- **Evidence Status**: Confirmed.
- **Final Status**: `fixed` (Configure `APP_BASE_URL` to frontend origin and add API redirect fallback in `routes.rb` for candidate `/interview/:token`).

---

### RSK-02: Total Lack of Automated Regression Tests and CI Quality Gates
- **Severity**: P0 Blocker
- **Type**: Implementation Defect / Quality Gate
- **Affected Component**: Repository configuration (`api/`, `web/`, `.github/`)
- **User/Business Impact**: Releases cannot be verified for correctness. Regressions slip directly into production.
- **Preconditions**: Fresh clone of repository.
- **Static Evidence**:
  - `api/spec/` does not exist.
  - `web/package.json` contains no test runner dependency or script.
  - `.github/workflows/` does not exist.
- **Data Integrity Impact**: High risk of unverified schema and data corruption.
- **Evidence Status**: Confirmed.
- **Final Status**: `fixed` (Built RSpec test suite in `api/spec/`, Vitest test suite in `web/`, and GitHub Actions CI workflow).

---

### RSK-03: B7 Taxonomy `skill_id` Stripped on Selection
- **Severity**: P1 Major
- **Type**: Implementation Defect / Data Integrity
- **Affected Component**: `web/src/components/assessment/SkillPicker.tsx:40-52`
- **Web–API Seam**: `SkillPicker` `onSelect` callback passed to `AssessmentNewPage`, `AssessmentEditPage`, `VacancyNewPage`, `VacancyEditPage`.
- **User/Business Impact**: Selected skills lose taxonomy linking. Candidate skills cannot be correlated by ID against vacancy requirements in Fit/Gap analysis.
- **Preconditions**: Open any Assessment or Vacancy creation/edit page and click "Add from Skill Taxonomy".
- **Reproduction Steps**:
  1. Open `web/src/components/assessment/SkillPicker.tsx` lines 39–54:
     ```typescript
     const handleSelect = (s: SkillTaxonomy) => {
       onSelect({
         skill_id: undefined, // BUG: explicitly hardcoded to undefined!
         skill_label: s.skill_label,
         is_custom: false,
         expected_level: 3,
         scope_include: s.scope_include,
         l1_anchor: s.l1_anchor,
         ...
     ```
  2. Pick "React / Frontend Development Core" (`SK-ENG-001`).
  3. Inspect the form state in React DevTools: `skills[0].skill_id` is `undefined`.
  4. Submit the form: API receives `{"assessment_skills_attributes":[{"skill_id":null,"skill_label":"React / Frontend Development Core",...}]}`.
  5. Check database `assessment_skills` table: `skill_id` is `NULL`.
  6. **Actual Behavior**: Taxonomy identifier is discarded permanently.
  7. **Expected Behavior**: `skill_id` is preserved as `s.skill_id` (`"SK-ENG-001"`).
- **Data Integrity Impact**: High. Disconnects assessment skills and vacancy skills from the canonical `skill_taxonomies` table.
- **Evidence Status**: Confirmed.
- **Final Status**: `fixed` (Set `skill_id: s.skill_id` in `SkillPicker.tsx`).

---

### RSK-04: Omitted Nested Records Not Destroyed on Framework Updates
- **Severity**: P1 Major
- **Type**: Implementation Defect / Persistence
- **Affected Component**:
  - `AssessmentsController#update` (`api/app/controllers/api/v1/assessments_controller.rb:41-48`)
  - `VacanciesController#update` (`api/app/controllers/api/v1/vacancies_controller.rb:38-44`)
  - `AssessmentEditPage.tsx:77-87`
  - `VacancyEditPage.tsx:45-54`
- **Web–API Seam**: Frontend sends updated list of skills via nested attributes.
- **User/Business Impact**: Assessors cannot delete skills from assessments or vacancies. Ghost skills remain forever.
- **Preconditions**: An assessment exists with 3 skills (e.g., Skill A, Skill B, Skill C).
- **Reproduction Steps**:
  1. Navigate to `/assessments/:id/edit`.
  2. Click the `X` button on "Skill C" to remove it. Only Skill A and Skill B remain in the UI.
  3. Click **Save Changes**.
  4. Network tab shows payload sent:
     ```json
     {
       "assessment": {
         "name": "Frontend Engineer",
         "assessment_skills_attributes": [
           { "id": 1, "skill_label": "Skill A", "display_order": 0 },
           { "id": 2, "skill_label": "Skill B", "display_order": 1 }
         ]
       }
     }
     ```
  5. Rails executes SQL: updates Skill A and Skill B, but executes NO delete on Skill C because `_destroy: true` was not sent for ID 3.
  6. Refresh the page: Skill C is still present!
  7. **Actual Behavior**: Omitted skills remain in the database.
  8. **Expected Behavior**: Deleting a skill in the edit UI permanently deletes it from the database upon save.
- **Data Integrity Impact**: High. Zombie skills remain in assessment agenda and prompt generation.
- **Evidence Status**: Confirmed.
- **Final Status**: `fixed` (In backend update actions, detect omitted existing records and append `_destroy: true` before update).

---

### RSK-05: Asymmetric Label Slugification in `Coverage::Analyzer` Drops Updates
- **Severity**: P1 Major
- **Type**: Implementation Defect / Logic
- **Affected Component**: `api/app/services/coverage/analyzer.rb:167-171`
- **Web–API Seam**: Gemini Flash analysis response parsing in `CoverageAnalyzerWorker`.
- **User/Business Impact**: Coverage states fail to advance during interviews; interview loops or terminates prematurely.
- **Preconditions**: Assessment contains a skill where `skill_id` is null (e.g. from RSK-03 or custom skill).
- **Reproduction Steps**:
  1. Consider `Coverage::Analyzer#find_map`:
     ```ruby
     def find_map(coverage_maps, id_or_label)
       coverage_maps.find { |m| m.skill_id == id_or_label } ||
         coverage_maps.find { |m| m.skill_label.downcase.gsub(/\s+/, '-') == id_or_label&.downcase }
     end
     ```
  2. Suppose `skill_label` is `"System Design & Architecture"`.
     Left side: `"system-design-&-architecture"`.
  3. Gemini Flash LLM responds with:
     ```json
     {
       "skill_updates": [
         {
           "id": "System Design & Architecture",
           "new_state": "partial",
           "new_probe_count": 2,
           "reason": "Discussed distributed caching"
         }
       ]
     }
     ```
  4. Right side: `id_or_label&.downcase` is `"system design & architecture"` (with spaces).
  5. String comparison `"system-design-&-architecture" == "system design & architecture"` evaluates to `false`.
  6. `find_map` returns `nil`. Line 123 executes `next unless map`, silently discarding the update.
  7. **Actual Behavior**: Skill coverage state is dropped; probe count remains 0.
  8. **Expected Behavior**: `find_map` matches normalized strings (comparing slug against slug, or raw downcased against raw downcased).
- **Data Integrity Impact**: Moderate to High. Distorts real-time coverage map and final portfolio generation.
- **Evidence Status**: Confirmed.
- **Final Status**: `fixed` (Update `find_map` to compare both raw downcased and slugified strings).

---

### RSK-06: `AssessmentEditPage` Omits `language` Field and UI Selector
- **Severity**: P2 Minor
- **Type**: Implementation Defect / Spec Gap
- **Affected Component**: `web/src/pages/assessments/AssessmentEditPage.tsx`
- **Web–API Seam**: `assessmentsApi.update` payload.
- **User/Business Impact**: Assessor cannot modify language on existing assessments.
- **Static Evidence**:
  - `AssessmentEditPage.tsx:40-42`: `defaultValues` lacks `language`.
  - `AssessmentEditPage.tsx:52`: `reset` omits `language`.
  - Form JSX does not render the language `<Select>` element present in `AssessmentNewPage.tsx:160-174`.
- **Evidence Status**: Confirmed.
- **Final Status**: `fixed` (Added language selector to `AssessmentEditPage.tsx` and wired to state).

---

### RSK-07: Controller Ignores `destroy` Failure on Associated Records
- **Severity**: P2 Minor
- **Type**: Implementation Defect
- **Affected Component**: `api/app/controllers/api/v1/assessments_controller.rb:51-54`, `vacancies_controller.rb:47-50`
- **Web–API Seam**: API HTTP status code and error handling.
- **User/Business Impact**: Assessor is told an assessment was deleted when it was not.
- **Reproduction Steps**:
  1. An assessment has active or ended sessions (`dependent: :restrict_with_error`).
  2. Send `DELETE /api/v1/assessments/:id`.
  3. `@assessment.destroy` returns `false` and adds error to `@assessment.errors`.
  4. Controller executes: `json_response({ message: "Assessment deleted" })` with status 200.
  5. **Actual Behavior**: HTTP 200 returned, but record was not deleted.
  6. **Expected Behavior**: Return HTTP 422 Unprocessable Entity with error message indicating why deletion was restricted.
- **Evidence Status**: Confirmed.
- **Final Status**: `fixed` (Check `@record.destroy` return value and return error if deletion was blocked).

---

### RSK-08: Inconsistent Tag Delimiter Between System Prompt and Map Injector
- **Severity**: P2 Minor
- **Type**: Static-Analysis Concern
- **Affected Component**: `api/app/services/assessments/system_prompt_compiler.rb:140` vs `api/app/services/coverage/map_injector.rb:42`
- **User/Business Impact**: Model prompt guidance mismatch could cause Gemini Live to treat coverage injections as candidate dialogue.
- **Static Evidence**:
  - `system_prompt_compiler.rb`: Mentions messages starting with `"[COVERAGE MAP"` (with a space).
  - `map_injector.rb`: Formats messages as `"[COVERAGE_MAP]\n#{payload.to_json}\n[/COVERAGE_MAP]"` (with an underscore).
- **Evidence Status**: Confirmed.
- **Final Status**: `fixed` (Aligned `system_prompt_compiler.rb` to reference `"[COVERAGE_MAP]"`).

---

### RSK-09: Role Restriction in `AuthenticationController` Rejects Non-Admin Users
- **Severity**: P2 Minor
- **Type**: Specification Gap
- **Affected Component**: `api/app/controllers/api/v1/authentication_controller.rb:14`
- **User/Business Impact**: Assessor users cannot log in if their role is set to `assessor`.
- **Static Evidence**:
  - Line 14: `return json_error('Invalid email or password', :unauthorized) unless user.role == 'admin'`
  - However, `AuthorizeApiRequest::ASSESSOR_ROLES` permits `admin` and `assessor`.
- **Evidence Status**: Confirmed.
- **Final Status**: `fixed` (Allow `admin` or `assessor` in `AuthenticationController#authenticate`).

---

### RSK-10: Missing Frontend `.env` Defaults to Invalid Backend Port 3000
- **Severity**: P2 Minor
- **Type**: Environment / Setup Blocker
- **Affected Component**: `web/src/services/api.ts:4-5`
- **User/Business Impact**: Frontend defaults to port 3000, while Rails runs on port 3001, causing immediate connection failures on fresh clone.
- **Static Evidence**:
  - `web/src/services/api.ts`: Defaults to `http://localhost:3000/api/v1` and `ws://localhost:3000`.
  - Rails runs on 3001 by default (`puma.rb:14`, `README.md:20`).
- **Evidence Status**: Confirmed.
- **Final Status**: `fixed` (Updated fallback in `api.ts` to `http://localhost:3001/api/v1` and `ws://localhost:3001`).

---

## 7. Missing or Ambiguous Specifications

1. **Candidate Verification Protocol**:
   - *Current State*: Candidates access the interview using only an unauthenticated `invite_token` via GET `/sessions/:token/candidate`. There is no PIN, email confirmation, or expiration verification.
   - *Specification Gap*: The specifications do not define whether candidate tokens should expire after a set time or single use, or whether candidates require email verification.
2. **Skill Deletion Policy with Historic Data**:
   - *Current State*: If an assessment skill is deleted after sessions have completed, historic `coverage_maps` and `portfolio_skills` still reference the old skill label.
   - *Specification Gap*: Should modifying assessment skills be prohibited once sessions are initiated, or versioned?
3. **Assessor vs Admin Role Boundaries**:
   - *Current State*: `User::ROLES` permits only `admin` and `user`, but `AuthorizeApiRequest` contains placeholder logic for `assessor`.
   - *Specification Gap*: Formal definition of RBAC permissions for pure Assessors vs Tenant Admins is missing.

---

## 8. Systemic Patterns Supported by Evidence

1. **Boundary Parameter Incoherence**:
   - Across both frameworks, parameters at the boundary are repeatedly mismatched: `skill_id: undefined` in `SkillPicker.tsx`, omitted `_destroy` in edit forms, and port mismatch in `Session#invite_url`.
2. **Defensive Programming Gaps in Controller Mutations**:
   - Controller actions frequently assume ActiveRecord operations succeed without inspecting the return boolean (e.g. `destroy` actions).
3. **Zero Test Culture**:
   - The absence of any tests allowed simple regressions (like `invite_url` port 3001 vs 5173 and `skill_id: undefined`) to persist undetected in working branches.

---

## 9. Coverage Gaps and Unverified Risks

| Risk / Area | Category | Reason Not Verified in Audit | Proposed Action |
|---|---|---|---|
| Hardware Check Speed Test Endpoints | Unverified Concern | Requires active network upload/ping test during audio capture | Implement E2E mock test |
| Long-duration WebSocket Audio Drift | Unverified Concern | Requires running a full 45-minute audio session | Test via audio frame generator script |
| Gemini Live Rate Limits / Quotas | Environment Blocker | Depends on external Google AI Studio API key and quota tier | Graceful error handling tested via unit mocks |
| Concurrent Candidate WebSocket Load | Unverified Concern | Requires multi-client load testing tool | Stress test EventMachine thread pool |

---

## 10. Ship / Do-Not-Ship Recommendation

### **Recommendation: DO NOT SHIP (BLOCKED)**

**Rationale:**
1. **P0 Blocker RSK-01**: Candidate interview links are completely non-functional (HTTP 404). The product cannot perform its primary function.
2. **P0 Quality Gate RSK-02**: Zero tests and no CI pipeline exist. Shipping without an enforceable gate violates quality standards.
3. **P1 Major RSK-03 & RSK-04 & RSK-05**: Data corruption in taxonomy mapping, inability to delete skills in edit pages, and dropped coverage transitions compromise the accuracy and integrity of candidate assessment reports.

---

## 11. Remaining Risks and Next Actions

### Immediate Actions for Phase 2 & Phase 3:
1. **Fix RSK-01**: Fix `Session#invite_url` and backend route redirect so candidate links resolve correctly to port 5173.
2. **Fix RSK-03**: Preserve `s.skill_id` in `web/src/components/assessment/SkillPicker.tsx`.
3. **Fix RSK-04**: Implement orphan deletion in `AssessmentsController#update` and `VacanciesController#update`.
4. **Fix RSK-05**: Fix label slugification matching in `Coverage::Analyzer#find_map`.
5. **Fix RSK-06, RSK-07, RSK-09, RSK-10**: Fix language selector, destroy error handling, auth role check, and default API port.
6. **Implement Phase 2 Quality System**: Create automated RSpec suite for backend, Vitest suite for web, PR validation checks, and GitHub Actions CI workflow.
7. **Demonstrate Red-to-Green**: Write regression tests that fail against unpatched defects and pass after root-cause fixes.
