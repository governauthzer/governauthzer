class AddScopeToApiTokens < ActiveRecord::Migration[8.1]
  def change
    # Action-scope (orthogonal to the existing source-scope): `full` = management
    # token (current default, all endpoints); `reconcile` = may ONLY post
    # reconciliation status. Bridge/handler tokens get `reconcile`.
    add_column :api_tokens, :scope, :string, null: false, default: "full"
  end
end
