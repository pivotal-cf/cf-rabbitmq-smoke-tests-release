# frozen_string_literal: true

require 'bosh/template/renderer'
require 'bosh/template/test'
require 'rspec/json_expectations'

module Bosh::Template::Test
  RSpec.describe 'smoke-tests job', template: true do
    let(:release_path) { File.join(File.dirname(__FILE__), '../..') }
    let(:release) { ReleaseDir.new(release_path) }
    let(:job) { release.job('smoke-tests') }
    let(:template) { job.template('config.json') }
    let(:merged_manifest_properties) do
      {
        'cf' => {
          'domain' => 'http://domain.io',
          'api_url' => 'http://api.io',
          'admin_username' => 'admin',
          'admin_password' => 'admin-secret',
          'admin_client' => 'admin-client',
          'admin_client_secret' => 'admin-client-secret'
        },
        'smoke_tests' => {
          'org' => 'my-org',
          'apps_domain' => 'cf.domain'
        }
      }
    end

    let(:rendered) { template.render(merged_manifest_properties) }

    describe 'config.json' do
      it 'should have all necessary properties' do
        expect(rendered).to include_json(
          api: 'http://api.io',
          apps_domain: 'cf.domain',
          skip_ssl_validation: true,
          admin_user: 'admin',
          admin_password: 'admin-secret',

          admin_client: 'admin-client',
          admin_client_secret: 'admin-client-secret',
          existing_client: 'admin-client',
          existing_client_secret: 'admin-client-secret',

          existing_organization: 'my-org',
          use_existing_organization: true,
          existing_space: '',
          use_existing_space: false,
          use_existing_user: false,
          service_offering: 'p-rabbitmq',
          tls_support: 'disabled',
          name_prefix: 'rmq-smoke-tests',
          timeout_scale: 30.0,
          plans: [{
            'name': 'standard'
          }]
        )
      end

      context 'when space is non-empty' do
        before(:each) do
          merged_manifest_properties['smoke_tests']['space'] = 'my-space'
        end

        it 'uses existing space' do
          expect(rendered).to include_json(
            existing_space: 'my-space',
            use_existing_space: true
          )
        end
      end
    end
  end
end
