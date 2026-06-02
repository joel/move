# frozen_string_literal: true

# Bit-position order matters: roles are stored as a bitmask (roles_mask)
# whose bit index is this array's index. Append new roles at the END;
# never reorder or remove existing entries without a data migration.
#
# :admin is the top tier. New accounts start with no roles (mask 0) — grant
# access explicitly.
Rails.configuration.roles = %i[admin contributor viewer].freeze
