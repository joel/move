# frozen_string_literal: true

module MoveMcp
  module Tools
    # Base for the MCP assistant tools (D13, Technical Foundation §14.2). Each
    # tool is an MCP::Tool subclass whose `self.call` runs entirely within the
    # token's Move — resolved from the server_context the McpController builds
    # (`{ move:, token:, actor: }`). Tools never reach across Moves or
    # Organizations: every record is loaded through `move`'s associations, which
    # are already isolated by the Apartment tenant schema.
    #
    # All mutations flow through the same shared app/actions as the web UI and
    # call `audit` so the action is recorded with source `mcp` (§14.4).
    class Base < MCP::Tool
      class << self
        # --- server_context accessors (a plain Hash, delegated by ServerContext) ---
        def move(context)  = context[:move]
        def token(context) = context[:token]
        def base_url(context) = context[:base_url]
        # Attribute MCP mutations to the token's owning user for the domain events
        # (Technical Foundation §14.1 step 4); the mcp.* audit names the token.
        def actor(context) = context[:token]&.created_by

        # --- responses ---
        def text_response(text)
          MCP::Tool::Response.new([{ type: "text", text: text.to_s }])
        end

        # JSON payload both as readable text (for the model) and structured_content.
        def data_response(data)
          MCP::Tool::Response.new(
            [{ type: "text", text: JSON.pretty_generate(data) }], structured_content: data
          )
        end

        def error_response(message)
          MCP::Tool::Response.new([{ type: "text", text: message.to_s }], error: true)
        end

        # Map an action Failure to a human-readable tool error. The archived
        # (read-only) Move guard now lives in the shared action (ensure_writable →
        # Failure(:move_archived)), so MCP mutating tools no longer pre-check — the
        # action's failure flows through here with a friendly message.
        def failure_response(failure)
          message = {
            move_archived: "This move is archived and is read-only.",
            wrong_phase: "That box isn't being unpacked — delete the item instead of marking it unpacked.",
            not_capturable: "That box is sealed — unseal it before adding to it.",
            no_file: "No upload was provided.",
            invalid_upload: "The upload could not be found — presign and PUT the bytes first.",
            image_too_large: "Image is too large (max #{Media::MAX_IMAGE_BYTES_LABEL}).",
            unsupported_image: "That file isn't a supported image (use JPEG, PNG, WEBP, HEIC, or TIFF)."
          }[failure]
          error_response(message || "Action failed: #{failure}")
        end

        # --- lookups (Move-scoped; nil → caller returns error_response) ---
        def find_box(context, number)
          move(context).boxes.find_by(number: number.to_s)
        end

        def find_item(context, id)
          move(context).items.find_by(id: id)
        end

        # --- audit (mutating tools call after a successful action) ---
        def audit(context, **details)
          MoveMcp::Audit.record(context, tool: tool_name, **details)
        end

        # --- serialisers ---
        def box_json(box)
          {
            number: box.number.to_i, status: box.status, room: box.room&.name,
            fragile: box.fragile?, item_count: box.items.in_box.count
          }
        end

        def item_json(item)
          {
            id: item.id, name: item.name, box_number: item.box.number.to_i,
            review_state: item.review_state, presence_state: item.presence_state
          }
        end
      end
    end
  end
end
