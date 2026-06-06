# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# ---------------------------------------------------------------------------
# Development demo data — for manually clicking through the end-user UI and the
# approval workflow. Guarded to development so it never pollutes test/prod.
# Idempotent (find_or_create_by); records are created directly (no service
# objects → no audit emission / Current needed). Log in afterwards with
#   bin/governauthzer emergency-login --user=<email> --reason=demo
# ---------------------------------------------------------------------------
if Rails.env.development?
  puts "Seeding development demo data…"

  # Operator (governauthzer-itself application + operator role + approved grant).
  govern = Application.find_or_create_by!(slug: Application::SELF_SLUG) { |a| a.name = "Governauthzer" }
  operator_role = govern.roles.find_or_create_by!(slug: "operator") do |r|
    r.name = "Operator"
    r.protected = true
  end

  # People: an operator, a manager, two of the manager's reports.
  operator = User.find_or_create_by!(email: "operator@example.com") { |u| u.name = "Olivia Operator"; u.status = "active" }
  manager  = User.find_or_create_by!(email: "manager@example.com")  { |u| u.name = "Marvin Manager";  u.status = "active" }
  ada      = User.find_or_create_by!(email: "ada@example.com")      { |u| u.name = "Ada Report";      u.status = "active" }
  ben      = User.find_or_create_by!(email: "ben@example.com")      { |u| u.name = "Ben Report";      u.status = "active" }
  [ ada, ben ].each { |u| u.update!(manager: manager) }

  Access.find_or_create_by!(user: operator, role: operator_role) do |acc|
    acc.status = "approved"
    acc.source = "manual"
    acc.justification = "dev seed"
  end

  # Approval workflow: the requester's manager approves, falling back to the operator.
  # Seeded under DEFAULT_SLUG so ApprovalWorkflow.default also resolves.
  workflow = ApprovalWorkflow.find_or_create_by!(slug: ApprovalWorkflow::DEFAULT_SLUG) { |w| w.name = "Manager approval" }
  if workflow.approval_steps.empty?
    workflow.approval_steps.create!(position: 0, strategy: "manager_of_requester", fallback_user: operator)
  end

  # Requestable demo apps + roles, all wired to the workflow.
  {
    "Slack"  => %w[Member Admin],
    "GitHub" => %w[Read Write],
    "AWS"    => %w[ReadOnly PowerUser]
  }.each do |app_name, role_names|
    app = Application.find_or_create_by!(slug: app_name.downcase) { |a| a.name = app_name }
    role_names.each do |role_name|
      app.roles.find_or_create_by!(slug: "#{app_name.downcase}-#{role_name.downcase}") do |r|
        r.name = "#{app_name} #{role_name}"
        r.approval_workflow = workflow
      end
    end
  end

  puts <<~OUT
    Done. Demo users (all active):
      operator@example.com  (operator — sees the Admin link)
      manager@example.com   (approver for ada & ben)
      ada@example.com       (report)
      ben@example.com       (report)

    Try it:
      1. bin/governauthzer emergency-login --user=ada@example.com --reason=demo
         → open the printed URL, request "Slack Member"
      2. bin/governauthzer emergency-login --user=manager@example.com --reason=demo
         → open the printed URL, approve it from the inbox
  OUT
end
