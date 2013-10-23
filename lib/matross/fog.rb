_cset(:fog_config) { "#{shared_path}/config/fog_config.yml" }
namespace :fog do

  desc "Creates the fog_config.yml in shared path"
  task :setup, :roles => :app do
    run "mkdir -p #{shared_path}/config"
    template "fog/fog_config.yml.erb", fog_config
  end
  after "deploy:setup", "fog:setup"

  desc "Updates the symlink for fog_config.yml for deployed release"
  task :symlink, :roles => :app do
    run "ln -nfs #{fog_config} #{release_path}/config/fog_config.yml"
  end
  after "bundle:install", "fog:symlink"

end
