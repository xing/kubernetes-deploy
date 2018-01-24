# frozen_string_literal: true

require 'erb'
require 'securerandom'
require 'yaml'
require 'json'

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

    def bind_template_variables(binding, variables)
      variables.each do |var_name, value|
        binding.local_variable_set(var_name, value)
      end
    end

    def find_partial(name)
      partial_names = [name + '.yaml.erb', name + '.yml.erb']
      @partials_dirs.each do |dir|
        partial_names.each do |partial_name|
          partial_path = File.join(dir, partial_name)
          return File.read(partial_path) if File.exist?(partial_path)
        end
      end
      raise FatalDeploymentError, "Could not find partial '#{name}' in any of #{@partials_dirs.join(':')}"
    end

    def render_template(filename, raw_template)
      return raw_template unless File.extname(filename) == ".erb"

      binding = TemplateContext.new(self).template_binding
      bind_template_variables(binding, template_variables)

      src = ERB.new(raw_template).result(binding)
      if src =~ /^--- *\n/m
        src
      else
        # Make sure indentation isn't a problem, by producing a single line of
        # parseable YAML. Note that JSON is a subset of YAML.
        JSON.generate(YAML.load(src))
      end
    rescue StandardError => e
      @logger.summary.add_paragraph("Error from renderer:\n  #{e.message.tr("\n", ' ')}")
      raise FatalDeploymentError, "Template '#{filename}' cannot be rendered"
    end

    class TemplateContext
      def initialize(renderer)
        @_renderer = renderer
      end

      def template_binding
        binding
      end

      def partial(partial, locals = {})
        binding = template_binding
        binding.local_variable_set("locals", locals)

        variables = @_renderer.template_variables.merge(locals)
        @_renderer.bind_template_variables(binding, variables)

        template = @_renderer.find_partial(partial)
        ERB.new(template).result(binding)
      end
    end
  end
end
