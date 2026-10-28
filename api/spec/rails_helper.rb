# frozen_string_literal: true

require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'

abort('The Rails environment is running in production mode!') if Rails.env.production?
require 'rspec/rails'

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.before(:suite) do
    # Ensure test organization exists in public.organizations
    ActiveRecord::Base.connection.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS public.organizations (
        id          BIGSERIAL PRIMARY KEY,
        name        VARCHAR(255) NOT NULL,
        scheme      VARCHAR(255) NOT NULL,
        identifier  VARCHAR(255) NOT NULL,
        host        VARCHAR(255) NOT NULL,
        alias_hosts VARCHAR[] NOT NULL DEFAULT '{}',
        config      JSONB NOT NULL DEFAULT '{}',
        created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    SQL

    unless Organization.exists?(scheme: 'test-corp')
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO public.organizations (name, scheme, identifier, host, alias_hosts, config, created_at, updated_at)
        VALUES ('Test Corp', 'test-corp', 'test-corp', 'localhost', '{}', '{}', NOW(), NOW())
        ON CONFLICT DO NOTHING;
      SQL
    end
  end

  config.before(:each) do
    org = Organization.find_by(scheme: 'test-corp') || Organization.first
    if org
      Current.organization = org
      Current.tenant_id = org.id
    end
  end

  config.after(:each) do
    Current.clear if defined?(Current)
  end
end
