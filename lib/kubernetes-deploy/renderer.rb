# frozen_string_literal: true

require 'erb'
require 'securerandom'

module KubernetesDeploy
  class Renderer
    def initialize(current_sha:, template_dir:, logger:, bindings: {})
      @current_sha = current_sha
      @template_dir = template_dir
      @partials_dirs =
        %w(partials ../partials).map { |d| File.expand_path(File.join(@template_dir, d)) }
      @logger = logger
      @bindings = bindings
      # Max length of podname is only 63chars so try to save some room by truncating sha to 8 chars
      @id = current_sha[0...8] + "-#{SecureRandom.hex(4)}" if current_sha
    end

    def template_variables
      {
        'current_sha' => @current_sha,
        'deployment_id' => @id,
      }.merge(@bindings)
    end

    def bind_template_variables(binding, variables = template_variables)
      variables.each do |var_name, value|
        binding.local_variable_set(var_name, value)
      end
    end

    def find_partial(name)
      partial_name = name + '.yaml.erb'
      @partials_dirs.each do |dir|
        partial_path = File.join(dir, partial_name)
        return File.read(partial_path) if File.exist?(partial_path)
      end
      raise FatalDeploymentError, "Could not find partial '#{partial_name}' in any of #{@partials_dirs.join(':')}"
    end

    def render_template(filename, raw_template)
      return raw_template unless File.extname(filename) == ".erb"

      erb_binding = binding
      bind_template_variables(erb_binding)
      erb_binding.eval <<~EVA, __FILE__, __LINE__ + 1
        def partial(partial, locals = {})
          partial_binding = binding
          self.bind_template_variables(partial_binding)
          self.bind_template_variables(partial_binding, locals)
          template = self.find_partial(partial)
          ERB.new(template).result(partial_binding)
        end
      EVA
      erb_template = ERB.new(raw_template)
      erb_template.result(erb_binding)
    rescue NameError => e
      @logger.summary.add_paragraph("Error from renderer:\n  #{e.message.tr("\n", ' ')}")
      raise FatalDeploymentError, "Template '#{filename}' cannot be rendered"
    end
  end
end
