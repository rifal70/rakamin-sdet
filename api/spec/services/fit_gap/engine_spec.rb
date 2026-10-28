# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FitGap::Engine, type: :service do
  let(:assessment) do
    Assessment.create!(name: 'Staff Engineer', time_limit_min: 45, created_by: 1)
  end

  let(:session) { Session.create!(assessment: assessment, status: 'ended') }
  let(:portfolio) { Portfolio.create!(session: session, generation_status: 'complete') }

  let(:vacancy) do
    Vacancy.create!(
      role_title: 'Staff Frontend Engineer',
      created_by: 1,
      vacancy_skills_attributes: [
        { skill_id: 'SK-ENG-001', skill_label: 'React / Frontend Development Core', expected_level: 3 },
        { skill_id: 'SK-ENG-003', skill_label: 'System Design & Architecture', expected_level: 4 },
        { skill_id: 'SK-ENG-004', skill_label: 'Database Design & SQL', expected_level: 3 }
      ]
    )
  end

  let!(:skill1) do
    portfolio.portfolio_skills.create!(
      skill_id: 'SK-ENG-001',
      skill_label: 'React / Frontend Development Core',
      ai_level: 3,
      ai_confidence: 'high',
      evidence: ['Demonstrated deep React state patterns'],
      competency_summary: 'Proficient React developer'
    )
  end

  let!(:skill2) do
    portfolio.portfolio_skills.create!(
      skill_id: 'SK-ENG-003',
      skill_label: 'System Design & Architecture',
      ai_level: 2,
      ai_confidence: 'medium',
      evidence: ['Basic microservice knowledge'],
      competency_summary: 'Needs growth in scaling'
    )
  end

  # Mock Gemini client to avoid external network calls during unit test
  let(:mock_gemini) do
    instance_double(Gemini::HttpClient, generate_content: {
      'culture_narrative' => 'Strong culture match.',
      'overall_narrative' => 'Recommended candidate.'
    })
  end

  subject(:engine) { described_class.new(portfolio: portfolio, vacancy: vacancy, gemini_client: mock_gemini) }

  describe '#call' do
    it 'accurately calculates match, gap, and not_assessed comparisons' do
      report = engine.call

      expect(report).to be_persisted
      comparisons = report.skill_comparisons

      # Skill 1: Candidate L3 vs Expected L3 -> match (delta 0)
      c1 = comparisons.find { |c| c['skill_id'] == 'SK-ENG-001' }
      expect(c1['result']).to eq('match')
      expect(c1['delta']).to eq(0)
      expect(c1['candidate_level']).to eq(3)

      # Skill 2: Candidate L2 vs Expected L4 -> gap (delta -2)
      c2 = comparisons.find { |c| c['skill_id'] == 'SK-ENG-003' }
      expect(c2['result']).to eq('gap')
      expect(c2['delta']).to eq(-2)
      expect(c2['candidate_level']).to eq(2)

      # Skill 3: Not in portfolio -> not_assessed
      c3 = comparisons.find { |c| c['skill_id'] == 'SK-ENG-004' }
      expect(c3['result']).to eq('not_assessed')
      expect(c3['candidate_level']).to be_nil
    end

    context 'when an assessor override is present' do
      before do
        # Override Skill 2 from L2 to L5
        AssessorOverride.create!(
          portfolio_skill: skill2,
          ai_level: 2,
          override_level: 5,
          overridden_by: 1,
          assessor_notes: 'Demonstrated staff-level architectural leadership'
        )
      end

      it 'uses the overridden level to compute exceeds' do
        report = engine.call
        c2 = report.skill_comparisons.find { |c| c['skill_id'] == 'SK-ENG-003' }

        # Overridden level is 5 vs Expected 4 -> exceed (delta +1)
        expect(c2['candidate_level']).to eq(5)
        expect(c2['result']).to eq('exceed')
        expect(c2['delta']).to eq(1)
      end
    end
  end
end
