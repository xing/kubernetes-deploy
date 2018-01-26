# frozen_string_literal: true
require 'test_helper'

class RendererTest < KubernetesDeploy::TestCase
  def setup
    super
    @renderer = KubernetesDeploy::Renderer.new(
      current_sha: "12345678",
      template_dir: fixture_path('for_unit_tests'),
      logger: logger,
      bindings: { "a" => "1", "b" => "2" }
    )
  end

  def test_can_render_template_with_correct_indentation
    expected = <<EOY
---
a: 1
b: 2
---
c: c3
d: d4
foo: bar
---
e: e5
f: f6
---
foo: baz
---
value: 4
step:
  value: 3
  step:
    value: 2
    step:
      value: 1
      result: 24
EOY
    actual = YAML.load_stream(render("partials_test.yaml.erb")).map do |t|
      YAML.dump(t)
    end.join
    assert_equal expected, actual
  end

  private

  def render(filename)
    raw_template = File.read(File.join(fixture_path('for_unit_tests'), filename))
    @renderer.render_template(filename, raw_template)
  end
end
