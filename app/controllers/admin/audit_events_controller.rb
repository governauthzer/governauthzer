class Admin::AuditEventsController < Admin::BaseController
  PER_PAGE = 50
  UUID_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  def index
    @event_types = AuditEvent.distinct.order(:event_type).pluck(:event_type)
    scope = filtered_scope
    @total = scope.count
    @page = [ params[:page].to_i, 1 ].max
    @pages = [ (@total / PER_PAGE.to_f).ceil, 1 ].max
    @events = scope.order(occurred_at: :desc, id: :desc)
                   .limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
  end

  def show
    @event = AuditEvent.find(params[:id])
  end

  private

  def filtered_scope
    scope = AuditEvent.all
    scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
    scope = scope.where(correlation_id: params[:correlation_id]) if uuid?(params[:correlation_id])
    scope = scope.where("actor_display ILIKE ?", "%#{params[:actor]}%") if params[:actor].present?

    if (from = parse_date(params[:from]))
      scope = scope.where("occurred_at >= ?", from.beginning_of_day)
    end
    if (to = parse_date(params[:to]))
      scope = scope.where("occurred_at < ?", to.next_day.beginning_of_day)
    end

    if params[:target_type].present? && uuid?(params[:target_id])
      scope = scope.where("targets @> ?", [ { "type" => params[:target_type], "id" => params[:target_id] } ].to_json)
    end

    scope
  end

  def uuid?(value)
    value.present? && value.match?(UUID_RE)
  end

  def parse_date(value)
    return nil if value.blank?
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
