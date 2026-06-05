# frozen_string_literal: true

require 'bosh/template/test'

module Bosh::Template::Test
  RSpec.describe 'on-demand-broker-smoke-tests config/config.env', template: true do
    let(:release_path) { File.join(File.dirname(__FILE__), '../..') }
    let(:release) { ReleaseDir.new(release_path) }
    let(:job) { release.job('on-demand-broker-smoke-tests') }
    let(:template) { job.template('config/config.env') }

    let(:base_properties) do
      {
        'cf' => {
          'api_url' => 'https://api.example.com',
          'org' => 'smoke-tests-org',
          'service_offering_name' => 'p.rabbitmq',
          'plans' => [{ 'name' => 'single-node' }]
        }
      }
    end

    def rendered_timeout_secs(props)
      output = template.render(props)
      match = output.match(/^export SMOKE_TEST_TIMEOUT_SECS="(\d+)"/)
      match && match[1].to_i
    end

    describe 'SMOKE_TEST_TIMEOUT_SECS' do
      context 'with the default smoke_tests_timeout (60m)' do
        it 'renders 3600 seconds' do
          expect(rendered_timeout_secs(base_properties)).to eq(3600)
        end
      end

      context 'when smoke_tests_timeout is given in minutes' do
        it 'converts minutes to seconds' do
          props = base_properties.merge('smoke_tests_timeout' => '5m')
          expect(rendered_timeout_secs(props)).to eq(300)
        end
      end

      context 'when smoke_tests_timeout is given in seconds' do
        it 'passes through unchanged' do
          props = base_properties.merge('smoke_tests_timeout' => '120s')
          expect(rendered_timeout_secs(props)).to eq(120)
        end
      end

      context 'when smoke_tests_timeout is given in hours' do
        it 'converts hours to seconds' do
          props = base_properties.merge('smoke_tests_timeout' => '2h')
          expect(rendered_timeout_secs(props)).to eq(7200)
        end
      end

      context 'when smoke_tests_timeout is given in days' do
        it 'converts days to seconds' do
          props = base_properties.merge('smoke_tests_timeout' => '1d')
          expect(rendered_timeout_secs(props)).to eq(86400)
        end
      end

      context 'when smoke_tests_timeout is a bare integer (no unit)' do
        it 'treats it as seconds' do
          props = base_properties.merge('smoke_tests_timeout' => '300')
          expect(rendered_timeout_secs(props)).to eq(300)
        end
      end

      context 'when smoke_tests_timeout is an invalid value' do
        it 'raises an error mentioning the invalid value' do
          props = base_properties.merge('smoke_tests_timeout' => 'bad-value')
          expect { template.render(props) }.to raise_error(RuntimeError, /Invalid smoke_tests_timeout 'bad-value'/)
        end
      end
    end
  end
end
