require 'grocer/push_connection'
require 'thread'

module Grocer
  class PushConnectionPool
    DEFAULT_POOL_SIZE = 5

    attr_reader :available, :condition, :lock, :options, :size, :used

    def initialize(options)
      @options   = options.dup
      @available = []
      @used      = []
      @size      = options.fetch(:pool_size, DEFAULT_POOL_SIZE)
      @condition = ConditionVariable.new
      @lock      = Mutex.new
    end

    def acquire
      connection = nil
      begin
        synchronize do
          if connection = available.pop
            used << connection
          elsif size > (available.size + used.size)
            connection = new_connection
            used << connection
          else
            condition.wait(lock)
          end
        end
      end until connection

      yield connection
    ensure
      release(connection)
    end

    def write(bytes)
      acquire { |connection| connection.write(bytes) }
    end

    private

    def new_connection
      PushConnection.new(options)
    end

    def release(connection)
      return unless connection

      synchronize do
        available << used.delete(connection)
        condition.signal
      end
    end

    def synchronize(&block)
      lock.synchronize(&block)
    end
  end
end
