# frozen_string_literal: true

require 'bosh/template/renderer'
require 'bosh/template/test'
require 'rspec/json_expectations'

module Bosh::Template::Test
  RSpec.describe 'on-demand-broker-smoke-tests job', template: true do
    let(:release_path) { File.join(File.dirname(__FILE__), '../..') }
    let(:release) { ReleaseDir.new(release_path) }
    let(:job) { release.job('on-demand-broker-smoke-tests') }
    let(:template) { job.template('config.json') }
    let(:merged_manifest_properties) do
      {
        'cf' => {
          'api_url' => 'http://api.io',
          'admin_username' => 'admin',
          'admin_password' => 'admin-secret',
          'admin_client' => 'admin-client',
          'admin_client_secret' => 'admin-client-secret',
          'org' => 'my-org',
          'service_offering_name' => 'p.rabbitmq',
          'plans' => [{ 'name' => 'single-node' }]
        }
      }
    end

    let(:rendered) { template.render(merged_manifest_properties) }

    def properties_with_new_plans(plans)
      properties = Marshal.load(Marshal.dump(merged_manifest_properties))
      properties['cf']['plans'] = plans
      properties
    end

    def rendered_custom_properties(properties)
      template.render(properties)
    end

    describe 'apps_domain' do
      context 'when smoke_tests_apps_domain is present' do
        it('is set to smoke_tests_apps_domain') do
          merged_manifest_properties['smoke_tests_apps_domain'] = 'apps.example.domain.io'


          expect(rendered).to include_json(
            apps_domain: 'apps.example.domain.io'
          )
        end
      end

      context 'when smoke_tests_apps_domain is empty' do
        it('is not set') do
          merged_manifest_properties['smoke_tests_apps_domain'] = ''

          expect(rendered).to_not include('apps_domain')
        end
      end

      context 'when smoke_tests_apps_domain is absent' do
        it('is set to cf api_url') do

          expect(rendered).to_not include('apps_domain')
        end
      end
    end

    describe 'config.json' do
      it 'should have all necessary properties' do
        expect(rendered).to include_json(
          api: 'http://api.io',
          admin_user: 'admin',
          admin_password: 'admin-secret',

          admin_client: 'admin-client',
          admin_client_secret: 'admin-client-secret',
          existing_client: 'admin-client',
          existing_client_secret: 'admin-client-secret',

          use_existing_user: false,
          use_existing_organization: true,
          existing_organization: 'my-org',
          existing_space: '',
          use_existing_space: false,
          name_prefix: 'rmq-smoke-tests',
          timeout_scale: 30.0,
          skip_ssl_validation: true,
          service_offering: 'p.rabbitmq',
          plans: [{
            'name': 'single-node'
          }],
          tls_support: 'disabled'
        )
      end

      context 'when space is non-empty' do
        before(:each) do
          merged_manifest_properties['cf']['space'] = 'my-space'
        end

        it 'uses existing space' do
          expect(rendered).to include_json(
            existing_space: 'my-space',
            use_existing_space: true
          )
        end
      end
    end

    describe 'plans' do
      context 'when no plans passed' do
        it 'should have no plans in the properties' do
          rendered_properties = rendered_custom_properties(properties_with_new_plans([]))
          expect(rendered_properties).to include_json(plans: [])
        end
      end

      context 'when plans with run_smoke_tests property is passed' do
        it 'should have plan in the properties' do
          rendered_properties = rendered_custom_properties(properties_with_new_plans([{ 'name' => 'multi-node' }]))
          expect(rendered_properties).to include_json(plans: [{ 'name' => 'multi-node' }])
        end
      end

      context 'when plans with no run_smoke_tests property is passed' do
        it 'should have plan based on run_smoke_tests property of the plan' do
          rendered_properties = rendered_custom_properties(properties_with_new_plans(
            [
              { 'name' => 'multi-node', 'run_smoke_tests' => true },
              { 'name' => 'single-node', 'run_smoke_tests' => false },
            ]
          ))
          expect(rendered_properties).to include_json(plans: [{ 'name' => 'multi-node' }])
        end
      end

      context 'when plans with run_smoke_tests with different value type is passed' do
        it 'should have no plan in the properties' do
          rendered_properties = rendered_custom_properties(properties_with_new_plans(
            [
              { 'name' => 'single-node', 'run_smoke_tests' => 'false' },
            ]
          ))
          expect(rendered_properties).to include_json(plans: [])
        end
      end
    end
  end
end
