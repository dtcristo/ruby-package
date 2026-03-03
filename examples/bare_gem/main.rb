$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'rb/package'

Faker = import('faker')::Faker

puts "Hello, #{Faker::Name.name}!"
