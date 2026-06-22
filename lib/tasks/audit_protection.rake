namespace :db do
  namespace :audit_protection do
    # Proves the audit-log role separation (db/grants.sql) actually took effect: the
    # restricted runtime role must be able to INSERT/SELECT audit_events but NOT
    # UPDATE/DELETE it. Run as part of deploy, after applying grants — exits non-zero
    # when protection is missing so it can gate a release.
    desc "Verify the app role cannot UPDATE/DELETE audit_events " \
         "(role from the first arg or GOVERNAUTHZER_APP_DB_ROLE)"
    task :verify, [ :role ] => :environment do |_t, args|
      role = args[:role].presence || ENV["GOVERNAUTHZER_APP_DB_ROLE"].presence
      if role.nil?
        abort "Provide the app role: bin/rails 'db:audit_protection:verify[governauthzer_app]' " \
              "or set GOVERNAUTHZER_APP_DB_ROLE"
      end

      conn = ActiveRecord::Base.connection
      bool = ActiveModel::Type::Boolean.new
      want = { "INSERT" => true, "SELECT" => true, "UPDATE" => false, "DELETE" => false }

      results =
        begin
          want.map do |priv, expected|
            has = bool.cast(conn.select_value(
              "SELECT has_table_privilege(#{conn.quote(role)}, 'audit_events', #{conn.quote(priv)})"
            ))
            [ priv, expected, has ]
          end
        rescue ActiveRecord::StatementInvalid => e
          abort "Could not check privileges (does role #{role.inspect} and table audit_events exist?): #{e.message}"
        end

      results.each do |priv, expected, has|
        puts "  [#{expected == has ? "OK " : "BAD"}] #{role} #{priv} audit_events: has=#{has} want=#{expected}"
      end

      if results.all? { |_priv, expected, has| expected == has }
        puts "audit-log protection verified for #{role}: append+read allowed, rewrite+erase denied."
      else
        $stdout.flush
        abort "audit-log protection NOT in effect for #{role}. Run db/grants.sql as the owner role."
      end
    end
  end
end
