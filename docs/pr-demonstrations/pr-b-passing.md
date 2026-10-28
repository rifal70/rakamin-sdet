## 1. Linked Specification / PRD
[01-audit.md](assessment/01-audit.md#rsk-01-p0-blocker--candidate-interview-invite-url-generates-invalid-port-and-fails-with-404)

## 2. Solution & Design Plan
Fix candidate invite URL generation in `Session#invite_url` to point to port 5173 (or `FRONTEND_URL` environment configuration) where the Vite web application runs. Add candidate interview route fallback redirect in `routes.rb` so accidental requests to API port 3001 gracefully redirect to the frontend.

## 3. Acceptance Criteria & Test Scenarios
- Scenario 1: `Session#invite_url` generates `http://localhost:5173/interview/<token>` when `FRONTEND_URL` is configured to port 5173.
- Scenario 2: Candidate hitting `http://localhost:3001/interview/<token>` on the API server is redirected to the web frontend application.
- Scenario 3: When `FRONTEND_URL` environment variable is set to a production domain, invite URLs use that origin.

## 4. Relevant Tests & Verification
- `api/spec/models/session_spec.rb`
- `web/tests/contracts.test.js`
- Manual verification: Generated invite link opens candidate onboarding and microphone check without 404 error.
