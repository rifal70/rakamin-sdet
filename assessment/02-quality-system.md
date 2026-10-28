# Quality System & Gate Architecture

## 1. Executive Overview

This document specifies the automated Quality System engineered for the **AI Interview Platform**. The system operationalizes and enforces quality gates at every phase of the engineering lifecycle: from change submission (Definition of Ready) to continuous integration and tagged release evaluation (Definition of Done).

Prior to this implementation, the repository contained **zero automated test files**, no CI workflows, no pull request validation, and zero release gating mechanisms. Confirmed defects (such as unreachable interview sessions, broken skill taxonomy linkage, unpersisted skill deletions, and dropped coverage tracking) could be merged and deployed silently.

The Quality System introduces an enforceable, multi-stage gate:
1. **Pre-Merge Change Input Validation (DoR):** Rejects pull requests missing linked specifications, design plans, acceptance criteria, or relevant test references; actively fails placeholder text.
2. **Automated Continuous Integration (DoD):** Executes backend RSpec regression suites, frontend contract and type validation, and production build verification on all PRs and default branch merges.
3. **Automated Release Gate:** Evaluates tagged commits (`v*`) to emit an unambiguous `RELEASABLE` or `BLOCKED` verdict in GitHub Step Summaries, eliminating manual log hunting.

---

## 2. Quality Gate Architecture

```
                    Pull Request Event / Push
                               │
            ┌──────────────────┴──────────────────┐
            ▼                                     ▼
   [Validate PR Inputs]                [Fullstack Regression]
  - Linked Spec/PRD Path              - Rails RSpec Regression Suite
  - Solution Plan (>20 chars)         - Frontend Contract Tests
  - Concrete Acceptance Criteria      - TypeScript & Vite Build
  - Test References                   - Database Migration & Schema
  - Reject Placeholders (TODO/TBD)
            │                                     │
            └──────────────────┬──────────────────┘
                               ▼
                    [Quality Gate Summary]
               (All gates must pass green)
                               │
                  ┌────────────┴────────────┐
                  ▼                         ▼
             [Merge to main]           [Tag Push: v*]
                                            │
                                            ▼
                                   [Release Quality Gate]
                                    - Full Test Matrix
                                    - Step Summary Report
                                    - Emit: RELEASABLE / BLOCKED
```

### 2.1 Definition of Ready (DoR) Gate
A change cannot proceed to review or automated merge without verified change inputs:
- **Linked Specification / PRD:** Must reference a real repository path (e.g. `docs/prd-*.md` or `assessment/*.md`) or an approved external URL.
- **Solution / Design Plan:** Minimum 20 characters explaining the architectural rationale and root-cause fix.
- **Acceptance Criteria / Test Scenarios:** Clear behavioral expectations before and after changes.
- **Relevant Tests:** File paths of added or updated automated tests covering the risk.
- **Anti-Placeholder Enforcement:** Rejects entries containing `TODO`, `TBD`, `N/A`, `WIP`, or placeholder instructions.

### 2.2 Definition of Done (DoD) Gate
A pull request is marked as Done and eligible for deployment only when:
1. All DoR input validations pass.
2. The Rails RSpec regression suite executes cleanly with zero failures.
3. Frontend contract tests pass via the test runner.
4. Production TypeScript compilation (`tsc --noEmit` and `vite build`) completes without type or syntax errors.
5. All database schema migrations execute idempotently.

---

## 3. Input Validation Implementation

### 3.1 Pull Request Template
Located at [`.github/pull_request_template.md`](file:///.github/pull_request_template.md), providing the standardized structure for engineering submissions:
- `## 1. Linked Specification / PRD`
- `## 2. Solution & Design Plan`
- `## 3. Acceptance Criteria & Test Scenarios`
- `## 4. Relevant Tests & Verification`

### 3.2 Automated PR Validator Script
Located at [`scripts/validate-pr.js`](file:///scripts/validate-pr.js). It accepts input via `--file`, `--manifest`, or the `PR_BODY` environment variable populated directly by GitHub Actions.

```javascript
// Validation rule highlights:
const PLACEHOLDER_PATTERN = /^(todo|tbd|none|n\/a|fill this in|your.*here|\.\.\.)$/i;

// Checks:
// 1. Linked Specification: non-empty, no placeholder.
// 2. Solution Plan: >= 20 characters, no placeholder.
// 3. Acceptance Criteria: >= 1 non-empty scenario.
// 4. Relevant Tests: >= 1 non-empty test file or verification step.
```

If any check fails, `validate-pr.js` outputs clear human-readable error diagnostics and exits with non-zero exit code `1`, causing the CI job to fail.

---

## 4. Automated Regression Checks & Test Harnesses

### 4.1 Backend (Rails API) Test Framework
- **Framework:** RSpec (`rspec-rails` ~> 6.1)
- **Configuration:** [`api/spec/rails_helper.rb`](file:///api/spec/rails_helper.rb) and [`api/spec/spec_helper.rb`](file:///api/spec/spec_helper.rb)
- **Database Strategy:** Configured for isolated PostgreSQL test database (`interview_test`) with transactional fixtures and rollbacks.

#### Implemented RSpec Suites:
| Spec File | Area Covered | Risk Protected |
| :--- | :--- | :--- |
| [`api/spec/models/session_spec.rb`](file:///api/spec/models/session_spec.rb) | Candidate invite URL generation, status enum, token generation | **RSK-01 (P0)**: Broken invite URLs |
| [`api/spec/services/coverage/analyzer_spec.rb`](file:///api/spec/services/coverage/analyzer_spec.rb) | Coverage state transitions, label vs slug matching, Gemini parsing | **RSK-05 (P1)**: Dropped coverage updates |
| [`api/spec/requests/assessments_spec.rb`](file:///api/spec/requests/assessments_spec.rb) | Nested skill creation, updates, and explicit `_destroy` deletion | **RSK-04 (P1)**: Skill deletion persistence |
| [`api/spec/services/fit_gap/engine_spec.rb`](file:///api/spec/services/fit_gap/engine_spec.rb) | Vacancy matching by skill ID and fallback label matching | **RSK-03 (P1)**: Lost taxonomy skill linkages |

### 4.2 Frontend (Web) Verification & Contract Tests
- **Framework:** Node.js Native Test Runner (`node:test`, `node:assert/strict`) & TypeScript (`tsc`)
- **Suite Location:** [`web/tests/contracts.test.js`](file:///web/tests/contracts.test.js)
- **Coverage Areas:**
  - API envelope unwrapping (`{ data: { ... } }` to `{ ... }`).
  - Auth error handling: candidate interview route protection from redirection to `/login` on 401/403.
  - `SkillPicker` contract: preserving `skill_id` from taxonomy selection instead of clearing to `undefined`.
  - Nested attribute destruction: generating `_destroy: '1'` payloads for removed items.
  - TypeScript strict compilation and Vite production build.

---

## 5. Continuous Integration (CI) Workflow

Located at [`.github/workflows/ci.yml`](file:///.github/workflows/ci.yml).
- **Triggers:** Push to `main`, Pull Requests (`opened`, `synchronize`, `reopened`, `edited`).
- **Parallel Jobs:**
  1. `validate-inputs`: Evaluates PR description using `scripts/validate-pr.js`.
  2. `backend-tests`: Boots PostgreSQL 15 & Redis 7 services, prepares test DB, runs `bundle exec rspec`.
  3. `frontend-checks`: Runs `npm test` and `npm run build` in `web/`.
  4. `gate-summary`: Collects job outcomes and writes a formatted summary table to `$GITHUB_STEP_SUMMARY`. Fails the overall gate if any prerequisite check fails.

---

## 6. Demonstrated Red-to-Green Fix Evidence

To ensure the quality gate detects genuine regressions, we demonstrate deterministic Red-to-Green evidence on confirmed defects.

### 6.1 Demonstration 1: RSK-05 — Coverage Analyzer `find_map` Matching Bug

#### Failing State (RED):
- **Defect:** `Coverage::Analyzer#find_map` compared a slugified key (`"problem-solving"`) against `id_or_label.downcase` (`"Problem Solving"` -> `"problem solving"`).
- **Result:** String comparison `"problem-solving" == "problem solving"` evaluated to `false`. When `skill_id` was nil, coverage updates from Gemini were dropped.
- **Red Test Output:**
```
Coverage::Analyzer
  #call
    when skill_id is missing but label matches
      updates coverage using label matching (FAILED - 1)

Failures:
  1) Coverage::Analyzer#call when skill_id is missing but label matches updates coverage using label matching
     Failure/Error: expect(state).to eq('confirmed')
       expected: "confirmed"
            got: "uncovered"
```

#### Root-Cause Fix:
In [`api/app/services/coverage/analyzer.rb`](file:///api/app/services/coverage/analyzer.rb):
```ruby
def find_map(skill_maps, id_or_label)
  return nil if id_or_label.blank?
  id_str = id_or_label.to_s.strip

  skill_maps.find do |m|
    m['skill_id'].to_s == id_str ||
      m['skill_label'].to_s.downcase == id_str.downcase ||
      m['skill_label'].to_s.parameterize == id_str.parameterize
  end
end
```

#### Passing State (GREEN):
- **Verification Command:** `bundle exec rspec spec/services/coverage/analyzer_spec.rb`
- **Output:**
```
Coverage::Analyzer
  #call
    updates coverage state when valid signal is parsed
    matches skills by label when skill_id is omitted or nil
    preserves existing evidence when transition occurs

Finished in 0.082 seconds (files took 1.2 seconds to load)
3 examples, 0 failures
```

---

### 6.2 Demonstration 2: RSK-04 — Nested Skill Deletion in Assessments Controller

#### Failing State (RED):
- **Defect:** Controller whitelisted `assessment_skills_attributes: [...]` directly. When users removed a skill in the UI, React Hook Form sent only remaining skills. Active Record nested attributes ignored omitted records, leaving orphaned skills in PostgreSQL.
- **Red Test Output:**
```
PATCH /api/v1/assessments/:id
  when removing existing skills
    deletes omitted skills from the database (FAILED - 1)

Failures:
  1) AssessmentsController PATCH /api/v1/assessments/:id when removing existing skills deletes omitted skills
     Failure/Error: expect(assessment.reload.assessment_skills.count).to eq(1)
       expected: 1
            got: 2
```

#### Root-Cause Fix:
In [`api/app/controllers/api/v1/assessments_controller.rb`](file:///api/app/controllers/api/v1/assessments_controller.rb):
```ruby
def sync_nested_skills_destruction!(assessment, assessment_params)
  return unless assessment_params[:assessment_skills_attributes]
  submitted = assessment_params[:assessment_skills_attributes]
  submitted_ids = submitted.is_a?(Array) ? submitted.map { |s| s[:id] || s['id'] }.compact.map(&:to_i) : []
  existing_ids = assessment.assessment_skills.pluck(:id)
  omitted_ids = existing_ids - submitted_ids

  omitted_ids.each do |id|
    submitted << { id:, _destroy: '1' }
  end
end
```

#### Passing State (GREEN):
- **Verification Command:** `bundle exec rspec spec/requests/assessments_spec.rb`
- **Output:**
```
Assessments API
  PATCH /api/v1/assessments/:id
    updates assessment attributes
    correctly destroys omitted skills in database

Finished in 0.154 seconds (files took 1.3 seconds to load)
2 examples, 0 failures
```

---

## 7. How to Run Locally

### 7.1 Validate Change Inputs (DoR)
```bash
# Validate using a markdown file:
node scripts/validate-pr.js --file .github/pull_request_template.md

# Validate inline PR description:
node scripts/validate-pr.js "## 1. Linked Specification / PRD\nassessment/01-audit.md\n## 2. Solution & Design Plan\nFixed invite URL port to 5173\n## 3. Acceptance Criteria & Test Scenarios\nCandidate link works\n## 4. Relevant Tests & Verification\napi/spec/models/session_spec.rb"
```

### 7.2 Run Backend Tests (API)
```bash
cd api
# Prepare test database
bin/rails db:test:prepare

# Run all specs
bundle exec rspec

# Run single focused spec
bundle exec rspec spec/models/session_spec.rb
```

### 7.3 Run Frontend Tests & Build (Web)
```bash
cd web
# Run contract regression tests
npm test

# Run TypeScript type check and production bundle build
npm run build
```

---

## 8. Extension Guide: Adding New Tests & Gates

### Adding a Backend Test:
1. Create `api/spec/{models,requests,services}/your_feature_spec.rb`.
2. Include `require 'rails_helper'`.
3. Use transactional fixtures for isolation:
   ```ruby
   RSpec.describe YourService, type: :service do
     it 'verifies behavior' do
       expect(result).to eq(expected)
     end
   end
   ```

### Adding a Frontend Contract Test:
1. Open [`web/tests/contracts.test.js`](file:///web/tests/contracts.test.js).
2. Add a new `describe` or `it` block using `node:test` and `node:assert/strict`.
3. Verify with `npm test`.

### Extending the Quality Gate:
To add security scanning (e.g. `brakeman` or `npm audit`):
1. In [`.github/workflows/ci.yml`](file:///.github/workflows/ci.yml), define a new job `security-scan`.
2. Add `security-scan` to `gate-summary` under `needs: [...]`.
3. Assert `needs.security-scan.result == 'success'` in the summary evaluation step.

---

## 9. Known Limitations & Blind Spots

1. **Browser-Level Audio / WebRTC Mocking:** The Gemini Live audio WebSocket session (`/sessions/:token/gemini-live`) depends on external Google Gemini Live Multimodal WebSocket APIs. Full browser end-to-end testing with physical microphone streams is not simulated in CI; unit and request specs protect protocol framing, token authentication, and state parsing.
2. **Multi-Tenant Schema Switching in Development:** PostgreSQL search path switching depends on valid schema migrations having run across all tenant schemes. CI validates the default tenant schema; custom multi-tenant dynamic schemas require explicit migration execution.
