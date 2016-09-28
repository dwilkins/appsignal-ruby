if DependencyHelper.capistrano3_present?
  require 'capistrano/all'
  require 'capistrano/deploy'
  require 'appsignal/capistrano'

  include Capistrano::DSL

  describe "Capistrano 3 integration" do
    let(:config) { project_fixture_config }
    let(:out_stream) { StringIO.new }
    let(:logger) { Logger.new(out_stream) }
    let!(:capistrano_config) do
      Capistrano::Configuration.reset!
      Capistrano::Configuration.env.tap do |c|
        c.set(:log_level, :error)
        c.set(:logger, logger)
        c.set(:rails_env, 'production')
        c.set(:repository, 'master')
        c.set(:deploy_to, '/home/username/app')
        c.set(:current_release, '')
        c.set(:current_revision, '503ce0923ed177a3ce000005')
      end
    end
    before do
      Rake::Task['appsignal:deploy'].reenable
    end
    around do |example|
      capture_std_streams(out_stream, out_stream) { example.run }
    end

    it "should have a deploy task" do
      Rake::Task.task_defined?('appsignal:deploy').should be_true
    end

    describe "appsignal:deploy task" do
      before do
        ENV['USER'] = 'batman'
        ENV['PWD'] = project_fixture_path
      end

      context "config" do
        it "should be instantiated with the right params" do
          Appsignal::Config.should_receive(:new).with(
            project_fixture_path,
            'production',
            {},
            kind_of(Logger)
          )
        end

        context "when appsignal_config is available" do
          before do
            capistrano_config.set(:appsignal_config, :name => 'AppName')
          end

          it "should be instantiated with the right params" do
            Appsignal::Config.should_receive(:new).with(
              project_fixture_path,
              'production',
              {:name => 'AppName'},
              kind_of(Logger)
            )
          end

          context "when rack_env is the only env set" do
            before do
              capistrano_config.delete(:rails_env)
              capistrano_config.set(:rack_env, 'rack_production')
            end

            it "should be instantiated with the rack env" do
              Appsignal::Config.should_receive(:new).with(
                project_fixture_path,
                'rack_production',
                {:name => 'AppName'},
                kind_of(Logger)
              )
            end
          end

          context "when stage is set" do
            before do
              capistrano_config.set(:rack_env, 'rack_production')
              capistrano_config.set(:stage, 'stage_production')
            end

            it "should prefer the stage rather than rails_env and rack_env" do
              Appsignal::Config.should_receive(:new).with(
                project_fixture_path,
                'stage_production',
                {:name => 'AppName'},
                kind_of(Logger)
              )
            end
          end

          context "when appsignal_env is set" do
            before do
              capistrano_config.set(:rack_env, 'rack_production')
              capistrano_config.set(:stage, 'stage_production')
              capistrano_config.set(:appsignal_env, 'appsignal_production')
            end

            it "should prefer the appsignal_env rather than stage, rails_env and rack_env" do
              Appsignal::Config.should_receive(:new).with(
                project_fixture_path,
                'appsignal_production',
                {:name => 'AppName'},
                kind_of(Logger)
              )
            end
          end
        end

        after do
          invoke('appsignal:deploy')
        end
      end

      describe "markers" do
        def stub_marker_request(data = {})
          stub_api_request config, 'markers', marker_data.merge(data)
        end

        let(:marker_data) do
          {
            :revision => '503ce0923ed177a3ce000005',
            :user => 'batman'
          }
        end

        context "when active for this environment" do
          it "transmits marker" do
            stub_marker_request.to_return(:status => 200)
            invoke('appsignal:deploy')

            expect(out_stream.string).to include \
              'Notifying Appsignal of deploy with: revision: 503ce0923ed177a3ce000005, user: batman',
              'Appsignal has been notified of this deploy!'
          end

          context "with overridden revision" do
            before do
              capistrano_config.set(:appsignal_revision, 'abc123')
              stub_marker_request(:revision => 'abc123').to_return(:status => 200)
              invoke('appsignal:deploy')
            end

            it "transmits the overriden revision" do
              expect(out_stream.string).to include \
                'Notifying Appsignal of deploy with: revision: abc123, user: batman',
                'Appsignal has been notified of this deploy!'
            end
          end

          context "with failed request" do
            before do
              stub_marker_request.to_return(:status => 500)
              invoke('appsignal:deploy')
            end

            it "does not transmit marker" do
              output = out_stream.string
              expect(output).to include \
                'Notifying Appsignal of deploy with: revision: 503ce0923ed177a3ce000005, user: batman',
                'Something went wrong while trying to notify Appsignal:'
              expect(output).to_not include 'Appsignal has been notified of this deploy!'
            end
          end
        end

        context "when not active for this environment" do
          before do
            capistrano_config.set(:rails_env, 'nonsense')
            invoke('appsignal:deploy')
          end

          it "should not send deploy marker" do
            expect(out_stream.string).to include \
              "Not notifying of deploy, config is not active for environment: nonsense"
          end
        end
      end
    end
  end
end
