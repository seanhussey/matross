dep_included? 'foreman'

set :foreman_user,  fetch(:user)
set :foreman_procs, {}

namespace :foreman do
  #TODO: Move from 'roles :all' to 'release_roles :all' implemented in 3.1
  #TODO: Remove previous 'bundle exec' configuration, use command mapping

  desc "Pre-setup, creates the shared upstart folder"
  task :pre_setup do
    on roles :all, exclude: :no_release do
      execute :mkdir, '-p', "#{shared_path}/upstart"
    end
  end

  desc "Merges all partial Procfiles and defines a specific dotenv"
  task :setup => :pre_setup do
    on roles :all, exclude: :no_release do
      execute :rm, "-f", "#{shared_path}/Procfile-matross"

      if test "[ -f '#{release_path}/Procfile' ]" then
        execute :cp, "#{release_path}/Procfile" , "#{shared_path}/Procfile-matross" 
      else
        execute :touch, "#{shared_path}/Procfile-matross" 
      end

      procfiles = capture(
        :find, shared_path, "-maxdepth", "1", "-name", "Procfile.*").split
      unless procfiles.empty?
        execute :cat, *procfiles, ">>#{shared_path}/Procfile-matross" 
        execute :rm, *procfiles
      end

      execute :echo, "RAILS_ENV=#{fetch(:rails_env).shellescape}",
        ">#{shared_path}/.env-matross"
      ["#{release_path}/.env", "#{release_path}/.env-#{fetch :stage}"].each do |f|
        execute :cat, f, ">>#{shared_path}/.env-matross" if test "[ -f '#{f}' ]"
      end
    end
  end

  desc "Symlink configuration scripts"
  task :symlink => :setup do
    on roles :all, exclude: :no_release do
      execute :ln, "-nfs", "#{shared_path}/Procfile-matross", release_path
      execute :ln, "-nfs", "#{shared_path}/.env-matross", release_path
    end
  end

  desc "Export the Procfile to Ubuntu's upstart scripts"
  task :export => :symlink do
    on roles :all, exclude: :no_release do
      execute :mkdir, '-p', "#{shared_path}/matross"
      # TODO: Make foreman template is overridable
      upload! File.expand_path("../../templates/foreman", __FILE__),
        "#{shared_path}/matross",
        :recursive => true

      # By default spawn one instance of every process
      procs = {}
      capture(:cat, "#{release_path}/Procfile-matross").split("\n").each do |line|
        process = line[/^([A-Za-z0-9_]+):\s*(.+)$/, 1]
        procs[process] = 1
      end
      procs.merge!(fetch :foreman_procs)

      proc_args = unless procs.empty? then
                    procs.inject("-c "){|a, o| a += "#{o[0]}=#{o[1]},"}.chop
                  else "" end

      within release_path do
        execute :foreman, "export", "upstart", "#{shared_path}/upstart",
          "-f", "Procfile-matross",
          "-a", "#{fetch :application}",
          "-u", "#{fetch :user}",
          "-l", "#{shared_path}/log",
          "-t", "#{shared_path}/matross/foreman",
          "-e", "#{release_path}/.env-matross",
          proc_args
      end

      sudo :cp, "#{shared_path}/upstart/*", "/etc/init/"
    end
  end

  desc "Symlink upstart logs to application shared/log"
  task :log => :export do
    on roles :all, exclude: :no_release do
      inits = capture(:find, "#{shared_path}/upstart", "-name", "*.conf").split
      inits.each do |init|
        logname = "#{File.basename(init).chomp(".conf")}.log"
        sudo :touch, "/var/log/upstart/#{logname}"
        sudo :chmod, "o+r", "/var/log/upstart/#{logname}"
        execute :ln, "-nfs", "/var/log/upstart/#{logname}", "#{shared_path}/log"
      end
    end
  end

  desc "(Re)start services"
  task :restart do
    on roles :all, exclude: :no_release do
      begin 
        sudo :start, fetch(:application)
      rescue SSHKit::Command::Failed
        sudo :restart, fetch(:application)
      end
    end
  end

  after :log, :restart
  after "deploy:updated", "foreman:log"

  desc "Stop services"
  task :stop do
    on roles :all, exclude: :no_release do
      sudo :stop, fetch(:application)
    end
  end

  desc "Remove upstart scripts"
  task :remove do
    on roles :all, exclude: :no_release do
      inits = capture(:find, "#{shared_path}/upstart", "-name", "*.conf").split
      inits.each do |init|
        init.chomp!(".conf")
        sudo :rm, "/etc/init/#{init}"
      end
    end
  end
end