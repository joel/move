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
    render_index
  end

  # POST /moves/:move_id/vocabularies/:kind
  def create
    authorize! @move, to: :create?, with: VocabularyPolicy

    result = Vocabularies::Create.new.call(
      move: @move, vocabulary: @vocabulary, params: vocab_params, actor: current_user
    )

    case result
    in Dry::Monads::Success(record)
      redirect_to move_vocabularies_path(@move, @vocabulary.kind), notice: t(".created", name: record.name)
    in Dry::Monads::Failure(errors)
      @new_record = @vocabulary.model.new(vocab_params)
      @new_record.errors.merge!(errors) if errors.respond_to?(:each)
      render_index(status: :unprocessable_content)
    end
  end

  # PATCH /moves/:move_id/vocabularies/:kind/:id
  def update
    authorize! @move, to: :update?, with: VocabularyPolicy

    result = Vocabularies::Update.new.call(
      record: @record, vocabulary: @vocabulary, params: vocab_params, actor: current_user
    )

    case result
    in Dry::Monads::Success(record)
      redirect_to move_vocabularies_path(@move, @vocabulary.kind), notice: t(".updated", name: record.name)
    in Dry::Monads::Failure
      # @record already carries the submitted (invalid) attributes + errors from
      # the failed save; render_index swaps it into the list so the inline edit
      # form reopens with the error shown.
      @editing = @record.id
      render_index(status: :unprocessable_content)
    end
  end

  # DELETE /moves/:move_id/vocabularies/:kind/:id
  def destroy
    authorize! @move, to: :destroy?, with: VocabularyPolicy

    result = Vocabularies::Remove.new.call(record: @record, vocabulary: @vocabulary, actor: current_user)

    case result
    in Dry::Monads::Success(detached)
      redirect_to move_vocabularies_path(@move, @vocabulary.kind),
                  notice: t(".removed", name: @record.name, count: detached)
    in Dry::Monads::Failure
      redirect_to move_vocabularies_path(@move, @vocabulary.kind), alert: t(".remove_failed")
    end
  end

  private

  def render_index(status: :ok)
    render(
      Views::Vocabularies::Index.new(
        move: @move,
        vocabulary: @vocabulary,
        records: records_for_index,
        usage_counts: @vocabulary.usage_counts(@move),
        can_edit: allowed_to?(:create?, @move, with: VocabularyPolicy),
        editing: @editing || params[:edit].presence,
        new_record: @new_record || @vocabulary.model.new
      ),
      status: status
    )
  end

  # The Move's values for this kind. On a failed inline rename, swap the
  # freshly-loaded copy of the edited record for the in-memory @record so the
  # row reopens with the submitted value + validation error.
  def records_for_index
    records = @vocabulary.records(@move).order(:name).to_a
    return records unless @record&.errors&.any?

    records.map { |r| r.id == @record.id ? @record : r }
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
