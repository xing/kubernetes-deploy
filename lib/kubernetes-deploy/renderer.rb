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
      @logger = logger
      @bindings = bindings
      # Max length of podname is only 63chars so try to save some room by truncating sha to 8 chars
      @id = current_sha[0...8] + "-#{SecureRandom.hex(4)}" if current_sha
    end

    def render_template(filename, raw_template)
      return raw_template unless File.extname(filename) == ".erb"

      erb_binding = TemplateContext.new(self).template_binding
      bind_template_variables(erb_binding, template_variables)

      ERB.new(raw_template).result(erb_binding)
    rescue StandardError => e
      @logger.summary.add_paragraph("Error from renderer:\n  #{e.message.tr("\n", ' ')}")
      raise FatalDeploymentError, "Template '#{filename}' cannot be rendered"
    end

    private

    def template_variables
      {
        'current_sha' => @current_sha,
        'deployment_id' => @id,
      }.merge(@bindings)
    end

    def bind_template_variables(erb_binding, variables)
      variables.each do |var_name, value|
        erb_binding.local_variable_set(var_name, value)
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

    class TemplateContext
      def initialize(renderer)
        @_renderer = renderer
      end

      def template_binding
        binding
      end

      def partial(partial, locals = {})
        erb_binding = template_binding
        erb_binding.local_variable_set("locals", locals)

        variables = @_renderer.__send__(:template_variables).merge(locals)
        @_renderer.__send__(:bind_template_variables, erb_binding, variables)

        template = @_renderer.__send__(:find_partial, partial)
        expanded_template = ERB.new(template, nil, '-').result(erb_binding)

        # If we're at top level we don't need to worry about the result being
        # included in another partial.
        return expanded_template if expanded_template =~ /^--- *\n/m

        # If we're not at the top level, we make sure indentation isn't a
        # problem, by producing a single line of parseable YAML. Note that JSON
        # is a subset of YAML.
        begin
          JSON.generate(YAML.load(expanded_template))
        rescue Psych::SyntaxError => e
          raise "#{e.class}#{e}. Partial did not expand to valid YAML, source: #{expanded_template}"
        end
      end
    end
  end
end
