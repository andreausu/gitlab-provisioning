#!/usr/bin/env bash

if [ -z "$1" ]; then
    echo "You must pass a domain name as a parameter. eg: ./bootstrap.sh gitlab.example.org"
    exit
fi

export DEBIAN_FRONTEND=noninteractive

GITLAB_DOMAIN=$1

echo "Configuring for domain $GITLAB_DOMAIN"

apt-get update
apt-get -y dist-upgrade
apt-get remove -y ruby

apt-get install -y python-software-properties

add-apt-repository -y ppa:git-core/ppa
add-apt-repository -y ppa:spuul/ruby

apt-get update

apt-get install -y git ruby2.0 ruby2.0-dev build-essential zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libreadline-dev libncurses5-dev libffi-dev curl redis-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev postfix mysql-server mysql-client libmysqlclient-dev nginx

# Bundler
gem install bundler --no-ri --no-rdoc

# System user
adduser --disabled-login --gecos 'GitLab' git

# GitLab shell

# Go to home directory
cd /home/git

# Clone gitlab shell
sudo -u git -H git clone https://github.com/gitlabhq/gitlab-shell.git

cd gitlab-shell

# switch to right version
sudo -u git -H git checkout v1.7.1

# Edit config and replace gitlab_url
# with something like 'http://domain.com/'
sudo -u git -H cp config.yml.example config.yml
sudo -u git -H ruby -pi -e "gsub(/http:\/\/localhost\//, 'http://$GITLAB_DOMAIN/')" config.yml

# Do setup
sudo -u git -H ./bin/install

# MySQL setup
MYSQL_ROOT_PASSWORD=`openssl rand -base64 20`
MYSQL_GITLAB_PASSWORD=`openssl rand -base64 20`
mysqladmin -u root password "$MYSQL_ROOT_PASSWORD"

mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER 'gitlab'@'localhost' IDENTIFIED BY '$MYSQL_GITLAB_PASSWORD';"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e 'CREATE DATABASE IF NOT EXISTS `gitlabhq_production` DEFAULT CHARACTER SET `utf8` COLLATE `utf8_unicode_ci`;'
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e 'GRANT SELECT, LOCK TABLES, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON `gitlabhq_production`.* TO gitlab@localhost;'


cd /home/git

# Clone GitLab repository
sudo -u git -H git clone https://github.com/gitlabhq/gitlabhq.git gitlab

# Go to gitlab dir
cd /home/git/gitlab

# Checkout to stable release
sudo -u git -H git checkout 6-1-stable


# Copy the example GitLab config
sudo -u git -H cp config/gitlab.yml.example config/gitlab.yml

# Make sure to change "localhost" to the fully-qualified domain name of your
# host serving GitLab where necessary

sudo -u git -H ruby -pi -e "gsub(/localhost/, '$GITLAB_DOMAIN')" config/gitlab.yml


# Make sure GitLab can write to the log/ and tmp/ directories
sudo chown -R git log/
sudo chown -R git tmp/
sudo chmod -R u+rwX  log/
sudo chmod -R u+rwX  tmp/

# Create directory for satellites
sudo -u git -H mkdir /home/git/gitlab-satellites

# Create directories for sockets/pids and make sure GitLab can write to them
sudo -u git -H mkdir tmp/pids/
sudo -u git -H mkdir tmp/sockets/
sudo chmod -R u+rwX  tmp/pids/
sudo chmod -R u+rwX  tmp/sockets/

# Create public/uploads directory otherwise backup will fail
sudo -u git -H mkdir public/uploads
sudo chmod -R u+rwX  public/uploads

# Copy the example Unicorn config
sudo -u git -H cp config/unicorn.rb.example config/unicorn.rb

# Configure Git global settings for git user, useful when editing via web
# Edit user.email according to what is set in gitlab.yml
sudo -u git -H git config --global user.name "GitLab"
sudo -u git -H git config --global user.email "gitlab@$GITLAB_DOMAIN"
sudo -u git -H git config --global core.autocrlf input


sudo -u git cp config/database.yml.mysql config/database.yml

sudo -u git -H ruby -pi -e "gsub(/root/, 'gitlab')" config/database.yml
sudo -u git -H ruby -pi -e "gsub(/secure password/, '$MYSQL_GITLAB_PASSWORD')" config/database.yml


# Install the gems
sudo gem install charlock_holmes --version '0.6.9.4'

# For MySQL (note, the option says "without ... postgres")
sudo -u git -H bundle install --deployment --without development test postgres aws

# Sets up the DB
sudo -u git -H bundle exec rake gitlab:setup RAILS_ENV=production force=yes

# Installs the init script
sudo cp lib/support/init.d/gitlab /etc/init.d/gitlab
sudo chmod +x /etc/init.d/gitlab
sudo update-rc.d gitlab defaults 21

# Starts the services
sudo service gitlab start


# Sets up nginx
sudo cp lib/support/nginx/gitlab /etc/nginx/sites-available/gitlab
sudo ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
sudo ruby -pi -e "gsub(/YOUR_SERVER_FQDN/, '$GITLAB_DOMAIN')" /etc/nginx/sites-available/gitlab

sudo service nginx restart

echo "MySQL root password: $MYSQL_ROOT_PASSWORD"
echo "MySQL gitlab password: $MYSQL_GITLAB_PASSWORD"
