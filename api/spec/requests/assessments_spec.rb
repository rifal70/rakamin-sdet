# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Assessments API', type: :request do
  let(:token) do
    JsonWebToken.encode({ user_id: 1, role: 'admin', scheme: 'test-corp' })
  end
  let(:headers) { { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' } }

  describe 'PUT /api/v1/assessments/:id' do
    let!(:assessment) do
      Assessment.create!(
        name: 'Initial Assessment',
        time_limit_min: 45,
        created_by: 1,
        language: 'en',
        assessment_skills_attributes: [
          {
            skill_label: 'Skill 1',
            expected_level: 3,
            display_order: 0,
            l1_anchor: 'L1', l2_anchor: 'L2', l3_anchor: 'L3', l4_anchor: 'L4', l5_anchor: 'L5'
          },
          {
            skill_label: 'Skill 2',
            expected_level: 4,
            display_order: 1,
            l1_anchor: 'L1', l2_anchor: 'L2', l3_anchor: 'L3', l4_anchor: 'L4', l5_anchor: 'L5'
          }
        ]
      )
    end

    it 'persists skill deletion when omitted from assessment_skills_attributes' do
      expect(assessment.assessment_skills.count).to eq(2)
      kept_skill = assessment.assessment_skills.find_by(skill_label: 'Skill 1')

      # Client submits only Skill 1 (Skill 2 was removed in UI)
      payload = {
        assessment: {
          name: 'Updated Assessment',
          time_limit_min: 45,
          language: 'en',
          assessment_skills_attributes: [
            { id: kept_skill.id, skill_label: 'Skill 1', expected_level: 3, display_order: 0 }
          ]
        }
      }

      put "/api/v1/assessments/#{assessment.id}", params: payload.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      assessment.reload
      expect(assessment.assessment_skills.count).to eq(1)
      expect(assessment.assessment_skills.first.skill_label).to eq('Skill 1')
      expect(AssessmentSkill.exists?(skill_label: 'Skill 2')).to be false
    end
  end

  describe 'DELETE /api/v1/assessments/:id' do
    let!(:assessment) do
      Assessment.create!(
        name: 'Protected Assessment',
        time_limit_min: 30,
        created_by: 1
      )
    end

    context 'when assessment has associated sessions' do
      let!(:session) { Session.create!(assessment: assessment) }

      it 'returns 422 unprocessable entity and preserves the record' do
        delete "/api/v1/assessments/#{assessment.id}", headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Assessment.exists?(id: assessment.id)).to be true
      end
    end

    context 'when assessment has no sessions' do
      it 'deletes the assessment cleanly' do
        delete "/api/v1/assessments/#{assessment.id}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(Assessment.exists?(id: assessment.id)).to be false
      end
    end
  end
end
