import { test, describe, it } from 'node:test';
import assert from 'node:assert/strict';

describe('Web - API Client Configuration & Envelope Interceptor', () => {
  it('correctly unwraps backend { data: { ... } } envelope', () => {
    // Replicate interceptor logic from web/src/services/api.ts
    const unwrapResponse = (response) => {
      if (response.data && typeof response.data === 'object' && 'data' in response.data) {
        response.data = response.data.data;
      }
      return response;
    };

    const mockResponse = {
      status: 200,
      data: {
        success: true,
        data: {
          assessment: { id: 42, name: 'Senior Fullstack Engineer', language: 'en' }
        }
      }
    };

    const result = unwrapResponse(mockResponse);
    assert.deepEqual(result.data, {
      assessment: { id: 42, name: 'Senior Fullstack Engineer', language: 'en' }
    });
  });

  it('guards candidate interview route from unauthorized redirect to /login', () => {
    // Interceptor logic for 401/403
    let redirectedTo = null;
    const handleAuthError = (status, pathname) => {
      if (status === 401 || status === 403) {
        if (!pathname.startsWith('/interview')) {
          redirectedTo = '/login';
        }
      }
    };

    // Candidate accessing session
    handleAuthError(403, '/interview/test-token-uuid');
    assert.equal(redirectedTo, null, 'Candidate interview route should NOT redirect to /login on 403');

    // Admin accessing dashboard
    handleAuthError(401, '/assessments');
    assert.equal(redirectedTo, '/login', 'Admin route should redirect to /login on 401');
  });
});

describe('Web - SkillPicker & Nested Attributes Contract (RSK-03 & RSK-04)', () => {
  it('preserves skill_id from taxonomy selection instead of assigning undefined', () => {
    const taxonomySkill = {
      id: 101,
      name: 'System Architecture',
      level_descriptions: { L1: 'Basic', L2: 'Developing', L3: 'Proficient', L4: 'Advanced', L5: 'Expert' }
    };

    // Replicate fixed SkillPicker handleSelect
    const buildSkillPayload = (selected) => {
      return {
        skill_id: selected.id, // RSK-03 fix
        skill_label: selected.name,
        target_score: 3,
        rubric_description: 'Evaluates architecture decisions',
        level_descriptions: selected.level_descriptions
      };
    };

    const payload = buildSkillPayload(taxonomySkill);
    assert.equal(payload.skill_id, 101, 'skill_id must be preserved from taxonomy');
    assert.equal(payload.skill_label, 'System Architecture');
  });

  it('correctly constructs _destroy flag for removed skills to ensure DB persistence sync', () => {
    const existingDbSkills = [
      { id: 1, skill_id: 10, skill_label: 'TypeScript' },
      { id: 2, skill_id: 11, skill_label: 'Ruby on Rails' },
      { id: 3, skill_id: 12, skill_label: 'PostgreSQL' }
    ];

    // Form submitted with item 2 deleted
    const submittedSkills = [
      { id: 1, skill_id: 10, skill_label: 'TypeScript' },
      { id: 3, skill_id: 12, skill_label: 'PostgreSQL' }
    ];

    // Replicate controller sync logic
    const submittedIds = submittedSkills.map(s => s.id).filter(Boolean);
    const existingIds = existingDbSkills.map(s => s.id);
    const omittedIds = existingIds.filter(id => !submittedIds.includes(id));

    const finalNestedParams = [...submittedSkills];
    omittedIds.forEach(id => {
      finalNestedParams.push({ id, _destroy: '1' });
    });

    assert.equal(finalNestedParams.length, 3);
    const destroyedItem = finalNestedParams.find(s => s.id === 2);
    assert.ok(destroyedItem, 'Omitted skill must have a _destroy entry');
    assert.equal(destroyedItem._destroy, '1');
  });
});
