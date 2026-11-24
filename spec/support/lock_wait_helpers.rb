# frozen_string_literal: true

# Helpers for the real-lock specs (#926): work runs on a second connection,
# and the test waits until THAT connection is queued behind a known one. A
# server-wide probe (`pg_locks WHERE NOT granted`) also counts unrelated
# waiters, such as another test process on the same server, so it could pass
# before the contention under test happened.
module LockWaitHelpers
  # The backend pid of the current thread's connection.
  def backend_pid
    Integer(ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()"))
  end

  # Runs the block on another connection in a thread. Returns the thread and
  # that connection's backend pid.
  def start_on_other_connection
    pid = Queue.new
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        pid << backend_pid
        yield
      end
    end
    [thread, pid.pop(timeout: 5) || raise("the other connection never started")]
  end

  # Bounded wait (no sleeps for correctness) until backend `waiter` is blocked
  # by backend `holder`. False if `thread` (the waiter's) finished first or the
  # wait timed out.
  def blocked_by?(waiter, holder, thread)
    sql = "SELECT #{Integer(holder)} = ANY(pg_blocking_pids(#{Integer(waiter)}))"
    250.times do
      return true if ActiveRecord::Base.connection.select_value(sql)
      return false unless thread.alive?

      sleep 0.02
    end
    false
  end
end

RSpec.configure { |config| config.include LockWaitHelpers }
