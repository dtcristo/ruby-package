$LOAD_PATH.unshift('../../lib')
require 'rb/package'

import('faker') => { Faker: faker }
Faker = faker

puts "Hello, #{Faker::Name.name}!"
