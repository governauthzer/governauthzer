module Api::Pagination
  extend ActiveSupport::Concern

  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  def paginate(scope)
    page = [ params[:page].to_i, 1 ].max
    per_page = clamp_per_page(params[:per_page].to_i)
    total = scope.count
    records = scope.offset((page - 1) * per_page).limit(per_page)

    response.headers["X-Total-Count"] = total.to_s
    response.headers["Link"] = build_link_header(page: page, per_page: per_page, total: total)
    records
  end

  private

  def clamp_per_page(raw)
    return DEFAULT_PER_PAGE if raw <= 0
    [ raw, MAX_PER_PAGE ].min
  end

  def build_link_header(page:, per_page:, total:)
    last_page = [ (total.to_f / per_page).ceil, 1 ].max
    links = []
    links << link_to_page(1, "first")
    links << link_to_page(last_page, "last")
    links << link_to_page(page - 1, "prev") if page > 1
    links << link_to_page(page + 1, "next") if page < last_page
    links.join(", ")
  end

  def link_to_page(target_page, rel)
    uri = URI.parse(request.url)
    query = Rack::Utils.parse_query(uri.query.to_s)
    query["page"] = target_page.to_s
    uri.query = Rack::Utils.build_query(query)
    %(<#{uri}>; rel="#{rel}")
  end
end
