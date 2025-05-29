# frozen_string_literal: true

require 'bosh/template/renderer'
require 'bosh/template/test'
require 'rspec/json_expectations'

module Bosh::Template::Test
  RSpec.describe 'on-demand-broker-smoke-tests job run.sh', template: true do
    let(:release_path) { File.join(File.dirname(__FILE__), '../..') }
    let(:release) { ReleaseDir.new(release_path) }
    let(:job) { release.job('on-demand-broker-smoke-tests') }
    let(:template) { job.template('bin/run') }
    let(:properties) do
      {
        'smoke_tests_timeout' => "100m"
      }
    end

    describe 'smoke-tests timeout' do
      context 'when smoke_tests_timeout is present' do
        it('is set to 100m') do
          expect(template.render(properties)).to include('export SMOKE_TESTS_TIMEOUT=100m')
        end
      end

      context 'when smoke_tests_timeout is empty' do
        it('is not set') do
          expect(template.render({})).to include('export SMOKE_TESTS_TIMEOUT=60m')
        end
      end
    end
  end
end
