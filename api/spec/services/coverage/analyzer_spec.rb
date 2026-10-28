# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coverage::Analyzer, type: :service do
  let(:assessment) do
    Assessment.create!(
      name: 'Fullstack Engineer',
      time_limit_min: 45,
      created_by: 1
    )
  end

  let(:session) do
    Session.create!(
      assessment: assessment,
      status: 'active',
      started_at: Time.current
    )
  end

  describe '#find_map' do
    let(:analyzer) { described_class.new(session: session) }

    context 'when skills have skill_id nil (from custom skills or taxonomy selection)' do
      let!(:map_frontend) do
        session.coverage_maps.create!(
          skill_id: nil,
          skill_label: 'React / Frontend Development Core',
          state: 'not_yet',
          probe_count: 0
        )
      end

      let!(:map_system_design) do
        session.coverage_maps.create!(
          skill_id: nil,
          skill_label: 'System Design & Architecture',
          state: 'not_yet',
          probe_count: 0
        )
      end

      it 'correctly finds map when Gemini returns the full label with spaces' do
        maps = session.coverage_maps.to_a
        found = analyzer.send(:find_map, maps, 'React / Frontend Development Core')
        expect(found).to eq(map_frontend)
      end

      it 'correctly finds map when Gemini returns a downcased label' do
        maps = session.coverage_maps.to_a
        found = analyzer.send(:find_map, maps, 'system design & architecture')
        expect(found).to eq(map_system_design)
      end

      it 'correctly finds map when Gemini returns a slugified identifier' do
        maps = session.coverage_maps.to_a
        found = analyzer.send(:find_map, maps, 'system-design-&-architecture')
        expect(found).to eq(map_system_design)
      end
    end

    context 'when skills have a valid skill_id' do
      let!(:map_with_id) do
        session.coverage_maps.create!(
          skill_id: 'SK-ENG-001',
          skill_label: 'React / Frontend Development Core',
          state: 'not_yet',
          probe_count: 0
        )
      end

      it 'finds map by skill_id' do
        maps = session.coverage_maps.to_a
        found = analyzer.send(:find_map, maps, 'SK-ENG-001')
        expect(found).to eq(map_with_id)
      end
    end
  end
end
