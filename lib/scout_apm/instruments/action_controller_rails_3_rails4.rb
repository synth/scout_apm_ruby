module ScoutApm
  module Instruments
    # instrumentation for Rails 3 and Rails 4 is the same.
    class ActionControllerRails3Rails4
      attr_reader :logger

      def initalize(logger=ScoutApm::Agent.instance.logger)
        @logger = logger
        @installed = false
      end

      def installed?
        @installed
      end

      def install
        @installed = true

        # We previously instrumented ActionController::Metal, which missed
        # before and after filter timing. Instrumenting Base includes those
        # filters, at the expense of missing out on controllers that don't use
        # the full Rails stack.
        if defined?(::ActionController)
          if defined?(::ActionController::Base)
            ScoutApm::Agent.instance.logger.info "Instrumenting ActionController::Base"
            ::ActionController::Base.class_eval do
              # include ScoutApm::Tracer
              include ScoutApm::Instruments::ActionControllerRails3Rails4Instruments
            end
          end

          if defined?(::ActionController::Metal)
            ScoutApm::Agent.instance.logger.info "Instrumenting ActionController::Metal"
            ::ActionController::Metal.class_eval do
              include ScoutApm::Instruments::ActionControllerMetalInstruments
            end
          end

          if defined?(::ActionController::API)
            ScoutApm::Agent.instance.logger.info "Instrumenting ActionController::Api"
            ::ActionController::API.class_eval do
              include ScoutApm::Instruments::ActionControllerRails3Rails4Instruments
            end
          end
        end
      end
    end

    module ActionControllerMetalInstruments
      def process(*args)
        req = ScoutApm::RequestManager.lookup
        req.annotate_request(:uri => scout_transaction_uri(request))

        # IP Spoofing Protection can throw an exception, just move on w/o remote ip
        req.context.add_user(:ip => request.remote_ip) rescue nil
        req.set_headers(request.headers)

        req.web!

        req.start_layer( ScoutApm::Layer.new("Controller", "#{controller_path}/#{action_name}") )
        begin
          super
        rescue
          req.error!
          raise
        ensure
          req.stop_layer
        end
      end

      # Given an +ActionDispatch::Request+, formats the uri based on config settings.
      def scout_transaction_uri(request)
        case ScoutApm::Agent.instance.config.value("uri_reporting")
        when 'path'
          request.path # strips off the query string for more security
        else # default handles filtered params
          request.filtered_path
        end
      end
    end

    module ActionControllerRails3Rails4Instruments
      def process_action(*args)
        req = ScoutApm::RequestManager.lookup

        # Check if this this request is to be reported instantly
        if instant_key = request.cookies['scoutapminstant']
          Agent.instance.logger.info "Instant trace request with key=#{instant_key} for path=#{path}"
          req.instant_key = instant_key
        end

        super
      end
    end
  end
end

