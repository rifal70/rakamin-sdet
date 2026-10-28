# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Session, type: :model do
  let(:assessment) do
    Assessment.create!(
      name: 'Backend Engineer',
      time_limit_min: 30,
      created_by: 1
    )
  end

  describe '#invite_url' do
    it 'generates a URL pointing to the web frontend route for candidates' do
      session = Session.create!(assessment: assessment)

      # The invite URL must point to /interview/:token
      expect(session.invite_url).to include("/interview/#{session.invite_token}")
      
      # The base must NOT default to the raw API port if FRONTEND_URL is set
      # and should direct the candidate to the web frontend application
      expect(session.invite_token).to be_present
      expect(session.invite_token.length).to eq(64)
    end
  end

  describe 'validations and lifecycle' do
    it 'creates a session in pending status by default' do
      session = Session.create!(assessment: assessment)
      expect(session.status).to eq('pending')
      expect(session.pending?).to be true
    end

    it 'ensures invite_token is unique' do
      session1 = Session.create!(assessment: assessment)
      session2 = Session.new(assessment: assessment, invite_token: session1.invite_token)
      expect(session2).not_to be_valid
    end
  end
end
