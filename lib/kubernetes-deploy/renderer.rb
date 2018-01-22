# frozen_string_literal: true

require 'erb'
require 'securerandom'

module KubernetesDeploy
  class Renderer
    def initialize(current_sha:, template_dir:, logger:, bindings: {})
      @current_sha = current_sha
      @template_dir = template_dir
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

    def partials_array(name)
      ["/partials/#{name}.y{a,}ml.erb", "../partials/#{name}.y{a,}ml.erb"].map do |d|
        File.join(File.expand_path(@template_dir), d)
      end
    end

    def find_partial(name)
      files = Dir.glob(partials_array(name))
      return File.read(files.first) if files.first
      raise FatalDeploymentError, "Partial '#{name}' not found. Looked for: #{partials_array(name).join(', ')}"
    end

    def render_template(filename, raw_template)
      return raw_template unless File.extname(filename) == ".erb"

      binding = TemplateContext.new(self).template_binding
      bind_template_variables(binding, template_variables)

      ERB.new(raw_template).result(binding)
    rescue NameError => e
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
