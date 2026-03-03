require 'colorize'

module Adventure
  class Character
    attr_reader :name, :title, :catchphrase

    def initialize
      # Faker is set up in adventure.rb (same box), accessible here via constant lookup
      @name = Faker::Name.name
      @title = Faker::Job.title
      @catchphrase = Faker::TvShows::StarTrek.villain
    end

    def to_s = "#{@name} the #{@title}".colorize(:cyan)
  end
end
