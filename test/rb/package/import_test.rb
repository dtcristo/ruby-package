# frozen_string_literal: true

require_relative '../../test_helper'

FIXTURES_DIR = File.expand_path('../../fixtures', __dir__)

class ImportTest < Minitest::Test
  def test_import_absolute_path
    result = import("#{FIXTURES_DIR}/single_export")
    user = result.new('Bob')
    assert_equal 'Hello, Bob!', user.greet
  end

  def test_import_hash_namespace
    result = import("#{FIXTURES_DIR}/hash_export")
    assert_respond_to result, :add
    assert_respond_to result, :subtract
    assert_respond_to result, :version
    assert_equal 3.14159, result::PI
  end

  def test_import_destructuring
    import("#{FIXTURES_DIR}/hash_export") => { add:, subtract:, version: }
    assert_equal 15, add.(10, 5)
    assert_equal 5, subtract.(10, 5)
    assert_equal '1.0.0', version
  end

  def test_import_fetch
    result = import("#{FIXTURES_DIR}/hash_export")
    assert_equal '1.0.0', result.fetch(:version)
    assert_in_delta 3.14159, result.fetch(:PI)
  end

  def test_import_fetch_values
    result = import("#{FIXTURES_DIR}/hash_export")
    pi, version = result.fetch_values(:PI, :version)
    assert_in_delta 3.14159, pi
    assert_equal '1.0.0', version
  end
end
