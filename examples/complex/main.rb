require_relative '../../lib/rb/package'

# Add all package lib dirs to $LOAD_PATH so packages can be imported by name.
packages_dir = File.expand_path('packages', __dir__)
Dir.glob("#{packages_dir}/*/lib") { |d| $LOAD_PATH.unshift(d) unless $LOAD_PATH.include?(d) }

# --- 1. Single Import ---
# Adventure package has its own gems.rb (faker ~> 3.0, colorize) with bundler/setup
Adventure = import 'adventure'

# --- 2. Namespace Import (hash export) ---
Quests = import 'quest'

# --- 3. Destructuring Import + fetch_values ---
# Loot has its own gems.rb (faker ~> 3.0) — each box gets an isolated Faker namespace
import('loot') => { random_drop:, VERSION: loot_version, FAKER_VERSION: loot_faker_version }

# --- 4. fetch_values ---
max_challenges, quest_version = Quests.fetch_values(:MAX_CHALLENGES, :version)

# --- 5. Constant access via namespace ---
QuestModule = Quests::Quest

puts '=' * 55
narrator = Adventure.create_narrator
hero = Adventure.create_character

narrator.announce("⚔️  #{hero} embarks on a quest!")
narrator.announce("   Catchphrase: \"#{hero.catchphrase}\"")
puts

quest = Quests.random_quest(difficulty: :hard)
narrator.announce("📜 Quest: #{quest[:name]} [#{quest[:difficulty]}]")
narrator.describe("Max challenges allowed: #{max_challenges}")
narrator.describe("Quest system v#{quest_version} | Loot system v#{loot_version}")
narrator.describe("Adventure faker v#{Adventure.faker_version} | Loot faker v#{loot_faker_version}")
puts

quest[:challenges].each_with_index do |challenge, i|
  narrator.describe("Challenge #{i + 1}: #{challenge}")
  item = random_drop.(difficulty: quest[:difficulty])
  narrator.describe("  → Loot: #{item}")
end

puts
narrator.victory("🏆 #{hero.name} conquers all challenges!")
puts '=' * 55

# Process.exit! skips Ruby VM GC/cleanup. Ruby::Box (experimental in 4.0) can
# crash during VM shutdown when multiple boxes loaded native-extension gems
# (e.g. concurrent-ruby, which faker depends on). The program logic is complete;
# we just bypass the known VM teardown bug.
Process.exit!(0)

