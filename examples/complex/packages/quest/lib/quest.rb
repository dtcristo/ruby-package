# Quest package entry point — no gem dependencies
# Add all sibling packages' lib dirs to $LOAD_PATH for cross-package imports.
packages_dir = File.expand_path('../..', __dir__)
Dir.glob("#{packages_dir}/*/lib") { |d| $LOAD_PATH.unshift(d) unless $LOAD_PATH.include?(d) }

require 'quest/challenge'

module Quest
  DIFFICULTY_LEVELS = %i[easy medium hard legendary].freeze

  def self.random_quest(difficulty: :medium)
    challenges = Challenge.generate(difficulty)
    { name: Challenge::QUEST_NAMES.sample, difficulty:, challenges: }
  end
end

export(
  Quest:,
  random_quest: Quest.method(:random_quest),
  MAX_CHALLENGES: 5,
  version: '1.0.0'
)
