require_relative 'dog'

class Cat
  def initialize
    @dog = Dog.new
  end

  def meow
    "meow"
  end

  def scratch
    @dog.wag_tail
  end
end
