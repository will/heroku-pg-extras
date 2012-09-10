require "heroku/command/base"

class Heroku::Command::Pg < Heroku::Command::Base

  # pg:blocking [database]
  #
  # see what queries are blocking your queries
  #
  def blocking
    sql = %q(
      select bl.pid as blocked_pid, a.usename as blocked_user,
        ka.current_query as blocking_statement, now() - ka.query_start as blocking_duration,
        kl.pid as blocking_pid, ka.usename as blocking_user, a.current_query as blocked_statement,
        now() - a.query_start as blocked_duration
 from pg_catalog.pg_locks bl
      join pg_catalog.pg_stat_activity a
      on bl.pid = a.procpid
      join pg_catalog.pg_locks kl
           join pg_catalog.pg_stat_activity ka
           on kl.pid = ka.procpid
      on bl.transactionid = kl.transactionid and bl.pid != kl.pid
 where not bl.granted)

   exec_sql(sql, find_uri)
  end

  # pg:locks [database]
  #
  # see what locks are held by what
  #
  def locks
    sql = %q(
   select
     pg_stat_activity.datname as db_name,pg_class.relname,pg_locks.transactionid, pg_locks.granted,
     pg_stat_activity.usename as username,substr(pg_stat_activity.current_query,1,30) as query_snippet, pg_stat_activity.query_start,
     age(now(),pg_stat_activity.query_start) as "age", pg_stat_activity.procpid
   from pg_stat_activity,pg_locks left
     outer join pg_class on (pg_locks.relation = pg_class.oid)
   where pg_stat_activity.current_query <> '<insufficient privilege>' and
      pg_locks.pid=pg_stat_activity.procpid and pg_locks.mode = 'ExclusiveLock' order by query_start)

   exec_sql(sql, find_uri)
  end

  # pg:ps [database]
  #
  # see what's goin' on
  #
  def ps
    sql = %q(
    select
      procpid,
      application_name as source,
      age(now(),query_start) as running_for,
      waiting,
      current_query as query
   from pg_stat_activity
   where
     current_query <> '<insufficient privilege>'
     AND current_query <> '<IDLE>'
     and procpid <> pg_backend_pid()
   order by 3 desc
   )

    exec_sql(sql, find_uri)
  end

  # pg:kill procpid [database]
  #
  # kill a query
  #
  # -f,--force  # really kill a query
  #
  def kill
    procpid = shift_argument
    output_with_bang "procpid must be a procpid" unless procpid && procpid.to_i != 0
    procpid = procpid.to_i

    cmd = options[:force] ? 'pg_terminate_backend' : 'pg_cancel_backend'
    sql = %Q(select #{cmd}(#{procpid});)

    exec_sql(sql, find_uri)
  end

  def find_uri
    attachment = hpg_resolve(shift_argument, "DATABASE_URL")
    if attachment.kind_of? Array
      uri = URI.parse( attachment.last )
    else
      uri = URI.parse( attachment.url )
    end
    uri
  end

  def exec_sql(sql, uri)
    begin
      ENV["PGPASSWORD"] = uri.password
      ENV["PGSSLMODE"]  = 'require'
      exec %Q(psql -c "#{sql}" -U #{uri.user} -h #{uri.host} -p #{uri.port || 5432} #{uri.path[1..-1]})
    rescue Errno::ENOENT
      output_with_bang "The local psql command could not be located"
      output_with_bang "For help installing psql, see http://devcenter.heroku.com/articles/local-postgresql"
      abort
    end
  end
end
