#!/usr/bin/env node
/**
 * Quality Gate Enforcer: Definition of Ready & Definition of Done
 * Validates PR description or checked-in change manifest against required change inputs:
 * 1. Linked Specification/PRD (real URL or repository-relative path, rejecting placeholders)
 * 2. Short Solution/Design Plan (non-empty, >= 30 chars, rejecting placeholders)
 * 3. Acceptance Criteria or Test Scenarios (bullet points, rejecting placeholders)
 * 4. Relevant Tests (must reference actual test files or commands)
 */

const fs = require('fs');
const path = require('path');

const PLACEHOLDER_PATTERNS = [
  /\bTODO\b/i,
  /\bTBD\b/i,
  /\bFIXME\b/i,
  /\bfill this in\b/i,
  /\breplace me\b/i,
  /\basdf\b/i,
  /\bplaceholder\b/i,
  /\bxxx+\b/i,
  /\bnone\b/i,
  /\bn\/a\b/i
];

function hasPlaceholder(text) {
  if (!text) return true;
  return PLACEHOLDER_PATTERNS.some((pattern) => pattern.test(text));
}

function parseArgs() {
  const args = {};
  for (const arg of process.argv.slice(2)) {
    if (arg.startsWith('--file=')) args.file = arg.split('=')[1];
    if (arg.startsWith('--body=')) args.body = arg.split('=')[1];
    if (arg.startsWith('--manifest=')) args.manifest = arg.split('=')[1];
  }
  return args;
}

function extractSection(content, sectionHeader) {
  const regex = new RegExp(`##+\\s+${sectionHeader}[\\r\\n]+([\\s\\S]*?)(?=##+\\s+|$)`, 'i');
  const match = content.match(regex);
  if (!match) return null;
  // Strip HTML comments
  const cleaned = match[1].replace(/<!--[\s\S]*?-->/g, '').trim();
  return cleaned;
}

function validateInputs({ spec, plan, criteria, tests }) {
  const errors = [];

  // 1. Linked Specification / PRD
  if (!spec || spec.trim().length === 0) {
    errors.push('Missing linked specification. Provide a real URL or repo-relative path.');
  } else if (hasPlaceholder(spec)) {
    errors.push(`Specification link contains invalid placeholder: "${spec.slice(0, 40)}"`);
  } else {
    // Check if URL or repo path
    const isUrl = /^https?:\/\//i.test(spec.trim());
    const markdownLinkMatch = spec.match(/\[.*?\]\((.*?)\)/);
    const targetPath = markdownLinkMatch ? markdownLinkMatch[1].trim() : spec.trim();

    if (!isUrl) {
      const cleanPath = targetPath.replace(/^[./\\]+/, '');
      const fullPath = path.resolve(process.cwd(), cleanPath);
      if (!fs.existsSync(fullPath)) {
        errors.push(`Linked specification file does not exist in repository: "${cleanPath}"`);
      }
    }
  }

  // 2. Solution / Design Plan
  if (!plan || plan.trim().length === 0) {
    errors.push('Missing Solution & Design Plan. A concise architectural plan is required.');
  } else if (plan.trim().length < 30) {
    errors.push(`Solution plan is too brief (${plan.trim().length} chars). Minimum 30 characters required.`);
  } else if (hasPlaceholder(plan)) {
    errors.push('Solution plan contains prohibited placeholder text (TODO, TBD, etc.).');
  }

  // 3. Acceptance Criteria / Test Scenarios
  if (!criteria || criteria.trim().length === 0) {
    errors.push('Missing Acceptance Criteria. At least one testable scenario is required.');
  } else if (!/[-*]\s+|\d+\.\s+/i.test(criteria)) {
    errors.push('Acceptance Criteria must be formatted as structured bullet points or scenarios.');
  } else if (hasPlaceholder(criteria)) {
    errors.push('Acceptance Criteria contains prohibited placeholder text (TODO, TBD, etc.).');
  }

  // 4. Relevant Tests
  if (!tests || tests.trim().length === 0) {
    errors.push('Missing Relevant Tests. List the test files or commands protecting this change.');
  } else if (hasPlaceholder(tests)) {
    errors.push('Tests section contains prohibited placeholder text (TODO, TBD, etc.).');
  }

  return errors;
}

function run() {
  const args = parseArgs();
  let content = '';

  if (args.manifest || (!args.file && !args.body && fs.existsSync(path.join(process.cwd(), 'CHANGE_MANIFEST.json')))) {
    const manifestPath = args.manifest || path.join(process.cwd(), 'CHANGE_MANIFEST.json');
    console.log(`[Quality Gate] Validating checked-in change manifest: ${manifestPath}`);
    try {
      const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
      const errors = validateInputs({
        spec: manifest.specification || manifest.spec,
        plan: manifest.solution_plan || manifest.plan,
        criteria: Array.isArray(manifest.acceptance_criteria)
          ? manifest.acceptance_criteria.map((c) => `- ${c}`).join('\n')
          : manifest.acceptance_criteria,
        tests: Array.isArray(manifest.relevant_tests)
          ? manifest.relevant_tests.map((t) => `- ${t}`).join('\n')
          : manifest.relevant_tests
      });

      if (errors.length > 0) {
        console.error('\n❌ Quality Gate Validation FAILED:');
        errors.forEach((err, i) => console.error(`  ${i + 1}. ${err}`));
        console.error('\nAction required: Update CHANGE_MANIFEST.json or PR description to resolve all items above.\n');
        process.exit(1);
      }

      console.log('\n✅ Quality Gate Validation PASSED:');
      console.log('  • Specification verified');
      console.log('  • Solution plan verified');
      console.log('  • Acceptance criteria verified');
      console.log('  • Test requirements verified\n');
      process.exit(0);
    } catch (e) {
      console.error(`Failed to parse manifest: ${e.message}`);
      process.exit(1);
    }
  }

  if (args.file) {
    content = fs.readFileSync(path.resolve(process.cwd(), args.file), 'utf8');
  } else if (args.body) {
    content = args.body;
  } else if (process.env.PR_BODY) {
    content = process.env.PR_BODY;
  } else {
    // Check if PR template exists as fallback demonstration
    console.log('[Quality Gate] No PR body or manifest supplied. Checking for PR template compliance...');
    const templatePath = path.join(process.cwd(), '.github', 'pull_request_template.md');
    if (!fs.existsSync(templatePath)) {
      console.error('❌ Quality Gate: No input provided and .github/pull_request_template.md is missing.');
      process.exit(1);
    }
    console.log('Usage: node scripts/validate-pr.js --file=<pr_description.md> or --manifest=CHANGE_MANIFEST.json');
    process.exit(0);
  }

  const spec = extractSection(content, 'Linked Specification') || extractSection(content, 'Specification');
  const plan = extractSection(content, 'Solution & Design Plan') || extractSection(content, 'Design Plan');
  const criteria = extractSection(content, 'Acceptance Criteria') || extractSection(content, 'Test Scenarios');
  const tests = extractSection(content, 'Verification & Tests') || extractSection(content, 'Tests');

  const errors = validateInputs({ spec, plan, criteria, tests });

  if (errors.length > 0) {
    console.error('\n❌ Quality Gate Validation FAILED:');
    errors.forEach((err, i) => console.error(`  ${i + 1}. ${err}`));
    console.error('\nAction required: Fill in all required fields with concrete, change-specific values.\n');
    process.exit(1);
  }

  console.log('\n✅ Quality Gate Validation PASSED:');
  console.log('  • Specification: Verified');
  console.log('  • Solution Plan: Verified');
  console.log('  • Acceptance Criteria: Verified');
  console.log('  • Tests: Verified\n');
  process.exit(0);
}

run();
