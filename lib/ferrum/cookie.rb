# frozen_string_literal: true

module Ferrum
  class Cookie
    def initialize(attributes)
      @attributes = attributes
    end

    def name
      @attributes["name"]
    end

    def value
      @attributes["value"]
    end

    def domain
      @attributes["domain"]
    end

    def path
      @attributes["path"]
    end

    def size
      @attributes["size"]
    end

    def secure?
      @attributes["secure"]
    end

    def httponly?
      @attributes["httpOnly"]
    end

    def session?
      @attributes["session"]
    end

    def expires
      if @attributes["expires"] > 0
        Time.at(@attributes["expires"])
      end
    end
  end
end
