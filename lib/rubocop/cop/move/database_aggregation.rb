# frozen_string_literal: true

module RuboCop
  module Cop
    module Move
      # Flags the "load rows into Ruby, then reduce them" shapes that AGENTS.md
      # §1 #5 forbids — an O(N)-rows-for-O(1)-answer regression. Push the aggregate
      # into SQL instead (`sum`/`minimum`/`maximum`/`count`/`average`,
      # `group(:x).count`, `pick(Arel.sql("MIN(x), MAX(x)"))`, `exists?`).
      #
      # Fires on a *terminal reducer* (`sum`, `min`, `max`, `count`, …) whose
      # receiver chain bottoms out at a row-load — `pluck(...)`, a no-arg `to_a`, or
      # `select { ... }` — walking *through* pure element transforms (`map`,
      # `compact`, …) so the classic `pluck(:n).map(&:to_i).max` regression (#283) is
      # caught, while a plain `pluck(...).map { reshape }` of an already-aggregated
      # result is not (`map` is a transform, not a reducer).
      #
      # Deliberately does NOT flag `group_by`: it is legitimately used on already
      # in-memory collections (e.g. a rendered, keyset-paginated page — the one
      # documented exception) and the receiver's type can't be inferred statically.
      # A genuine in-memory case can opt out with a one-line inline disable
      # directive naming this cop, plus a reason.
      #
      # @example
      #   # bad
      #   Box.where(move:).pluck(:number).max
      #   Box.where(move:).pluck(:number).map(&:to_i).max
      #   box.items.select { |i| i.fragile? }.count
      #
      #   # good
      #   Box.where(move:).maximum(:number)
      #   box.items.where(fragile: true).count
      class DatabaseAggregation < Base
        MSG = "Aggregate in the database, not Ruby (AGENTS.md §1 #5): this reduces " \
              "rows loaded by `%<loader>s` in Ruby. Use a SQL aggregate " \
              "(sum/minimum/maximum/count/average, group(:x).count, pick(Arel.sql(...)))."

        # Terminal calls that compute a single value from a collection.
        REDUCERS = %i[sum min max minmax count size length reduce inject average].freeze
        # Pure element transforms to walk through when hunting the underlying load.
        TRANSFORMS = %i[map flat_map collect compact flatten uniq reverse sort sort_by tally].freeze

        def on_send(node)
          return unless REDUCERS.include?(node.method_name)

          loader = row_load_in_chain(node.receiver)
          return unless loader

          add_offense(node, message: format(MSG, loader: loader))
        end

        private

        # Walk down the receiver chain through pure transforms; return a label for
        # the row-load at the bottom (or nil if the chain is a plain relation, which
        # keeps the reducer in SQL).
        def row_load_in_chain(node)
          current = node
          while (send_node = send_node_for(current))
            label = loader_label(send_node, current)
            return label if label
            return nil unless TRANSFORMS.include?(send_node.method_name)

            current = send_node.receiver
          end
        end

        # Labels a row-loading call: `pluck(...)`, a no-arg `to_a`, or a
        # `select { ... }` block (a relation projection `select(:col)` is not one).
        def loader_label(send_node, node)
          case send_node.method_name
          when :pluck then "pluck(...)"
          when :to_a then ("to_a" if send_node.arguments.empty?)
          when :select then ("select { ... }" if node.block_type?)
          end
        end

        def send_node_for(node)
          return nil unless node

          node.block_type? ? node.send_node : (node if node.send_type?)
        end
      end
    end
  end
end
