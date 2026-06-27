# frozen_string_literal: true

# D2 — Controlled vocabularies (categories / tags / rooms). A single controller
# serves all three sibling surfaces: the `:kind` route segment resolves to a
# Vocabulary registry object that supplies the model, association, chip tint and
# usage counts. Runs inside an Organization tenant schema, scoped to one Move.
# Thin: authorize → call the action → pattern-match → render.
#
# Viewing is open to any member; adding / renaming / removing is admin-only and
# only on a writable Move (VocabularyPolicy, record = Move).
class VocabulariesController < MoveScopedController
  before_action :set_vocabulary
  before_action :set_record, only: %i[update destroy]

  # GET /moves/:move_id/vocabularies/:kind
  def index
    authorize! @move, to: :index?, with: VocabularyPolicy
    render Views::Vocabularies::Index.new(
      move: @move, vocabulary: @vocabulary, records: records, usage_counts: usage_counts,
      can_edit: can_edit?
    )
  end

  # POST /moves/:move_id/vocabularies/:kind — streams the new value into the list
  # (re-sorted + highlighted) with a toast; the add form clears for the next one.
  def create
    authorize! @move, to: :create?, with: VocabularyPolicy

    result = Vocabularies::Create.new.call(
      move: @move, vocabulary: @vocabulary, params: vocab_params, actor: current_user
    )

    case result
    in Dry::Monads::Success(record)
      respond_with_streams([list_stream(highlight_id: record.id)], redirect: index_path, toast: true) do
        [:notice, t(".created", name: record.name)]
      end
    in Dry::Monads::Failure(errors)
      new_record = @vocabulary.model.new(vocab_params)
      new_record.errors.merge!(errors) if errors.respond_to?(:each)
      # Re-render the add form (with the field error) and toast — non-2xx so the
      # reset-form controller leaves the typed value intact.
      respond_with_streams([add_form_stream(new_record)], redirect: index_path,
                                                          toast: true, status: :unprocessable_content) do
        [:alert, new_record.errors.full_messages.first.presence || t(".create_failed")]
      end
    end
  end

  # PATCH /moves/:move_id/vocabularies/:kind/:id — rename. Success re-renders the
  # whole list (so the row lands at its new sorted position, highlighted); a
  # rejected rename re-renders just that row with the inline edit form re-opened.
  def update
    authorize! @move, to: :update?, with: VocabularyPolicy

    result = Vocabularies::Update.new.call(
      record: @record, vocabulary: @vocabulary, params: vocab_params, actor: current_user
    )

    case result
    in Dry::Monads::Success(record)
      respond_with_streams([list_stream(highlight_id: record.id)], redirect: index_path, toast: true) do
        [:notice, t(".updated", name: record.name)]
      end
    in Dry::Monads::Failure
      # @record carries the submitted (invalid) attributes + errors.
      respond_with_streams([row_stream(@record, open: true)], redirect: index_path,
                                                              toast: true, status: :unprocessable_content) do
        [:alert, @record.errors.full_messages.first.presence || t(".update_failed")]
      end
    end
  end

  # DELETE /moves/:move_id/vocabularies/:kind/:id — streams the row out (no
  # reload); flips to the empty state on the last value.
  def destroy
    authorize! @move, to: :destroy?, with: VocabularyPolicy

    result = Vocabularies::Remove.new.call(record: @record, vocabulary: @vocabulary, actor: current_user)

    case result
    in Dry::Monads::Success(detached)
      respond_with_streams(destroy_streams, redirect: index_path, toast: true) do
        [:notice, t(".removed", name: @record.name, count: detached)]
      end
    in Dry::Monads::Failure
      respond_with_streams([], redirect: index_path, toast: true, status: :unprocessable_content) do
        [:alert, t(".remove_failed")]
      end
    end
  end

  private

  def index_path
    move_vocabularies_path(@move, @vocabulary.kind)
  end

  def can_edit?
    allowed_to?(:create?, @move, with: VocabularyPolicy)
  end

  def records
    @vocabulary.records(@move).order(:name).to_a
  end

  def usage_counts
    @vocabulary.usage_counts(@move)
  end

  # Replace the whole stable list wrapper — the created/renamed row lands at its
  # sorted position (records are name-ordered) and the empty↔populated boundary is
  # handled in one place. Always replace this guaranteed-present wrapper rather
  # than appending to a maybe-absent rows container.
  def list_stream(highlight_id: nil)
    turbo_stream.replace(
      Components::Vocabularies::List::ID,
      view_context.render(Components::Vocabularies::List.new(
                            move: @move, vocabulary: @vocabulary, records: records,
                            usage_counts: usage_counts, can_edit: can_edit?, highlight_id: highlight_id
                          ))
    )
  end

  def row_stream(record, open: false)
    turbo_stream.replace(
      Components::Vocabularies::Row.dom_id(record),
      view_context.render(Components::Vocabularies::Row.new(
                            move: @move, vocabulary: @vocabulary, record: record,
                            usage_count: usage_counts[record.id].to_i, can_edit: can_edit?, open: open
                          ))
    )
  end

  def add_form_stream(record)
    turbo_stream.replace(
      Components::Vocabularies::AddForm::ID,
      view_context.render(Components::Vocabularies::AddForm.new(
                            move: @move, vocabulary: @vocabulary, record: record
                          ))
    )
  end

  # Remove the row; when it was the last value, also replace the list so the empty
  # state takes over.
  def destroy_streams
    streams = [turbo_stream.remove(Components::Vocabularies::Row.dom_id(@record))]
    streams << list_stream if records.empty?
    streams
  end

  def set_vocabulary
    @vocabulary = Vocabulary.find(params.expect(:kind))
    head :not_found unless @vocabulary
  end

  def set_record
    @record = @vocabulary.records(@move).find(params.expect(:id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def vocab_params
    params.expect(vocabulary: @vocabulary.permitted_params).to_h.symbolize_keys
  rescue ActionController::ParameterMissing
    {}
  end
end
