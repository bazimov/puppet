#~/bin/bash

#Instructions to install puppet modules and so on

wget https://dl.bintray.com/mitchellh/vagrant/vagrant_1.7.2_x86_64.rpm
sudo rpm -ivh vagrant_1.7.2_x86_64.rpm
mkdir /vagrant\ up
cd /vagrant\ up
vagrant login
sudo su -
puppet module install puppetlabs-ntp
cp ~/Desktop/site.pp /vagrant\ up
puppet apply site.pp
sudo puppet module install puppetlabs-apache
sudo puppet module install puppetlabs-mysql

sudo puppet module list
mkdir ~/MyModules
cd ~/MyModules
puppet module generate do-wordpress --skip-interview
yum install vim -y
echo "{
  "name": "do-wordpress",
  "version": "0.1.0",
  "author": "do",
  "summary": null,
  "license": "Apache 2.0",
  "source": "",
  "project_page": null,
  "issues_url": null,
  "dependencies": [
    {"name":"puppetlabs/stdlib","version_requirement":">= 1.0.0"}
  ]
}
" > ~/MyModules/do-wordpress/metadata.json

echo "
class wordpress::web {

    # Install Apache
    class {'apache': 
        mpm_module => 'prefork'
    }

    # Add support for PHP 
    class {'::apache::mod::php': }
}
" > ~/MyModules/do-wordpress/manifests/web.pp

echo "
class wordpress::conf {
    # You can change the values of these variables
    # according to your preferences

    $root_password = 'password'
    $db_name = 'wordpress'
    $db_user = 'wp'
    $db_user_password = 'password'
    $db_host = 'localhost'

    # Don't change the following variables

    # This will evaluate to wp@localhost
    $db_user_host = "${db_user}@${db_host}"

    # This will evaluate to wp@localhost/wordpress.*
    $db_user_host_db = "${db_user}@${db_host}/${db_name}.*"
}
"
~/MyModules/do-wordpress/manifests/conf.pp
echo "
class wordpress::db {

    class { '::mysql::server':

        # Set the root password
        root_password => $wordpress::conf::root_password,

        # Create the database
        databases => {
            "${wordpress::conf::db_name}" => {
                ensure => 'present',
                charset => 'utf8'
            }
        },

        # Create the user
        users => {
            "${wordpress::conf::localhost}" => {
                ensure => present,
                password_hash => mysql_password("${wordpress::conf::password}")
            }
        },

        # Grant privileges to the user
        grants => {
            "${wordpress::conf::db_user_host_db}" => {
                ensure     => 'present',
                options    => ['GRANT'],
                privileges => ['ALL'],
                table      => "${wordpress::conf::db_name}.*",
                user       => "${wordpress::conf::db_user_host}",
            }
        },
    }

    # Install MySQL client and all bindings
    class { '::mysql::client':
        require => Class['::mysql::server'],
        bindings_enable => true
    }
}
" > ~/MyModules/do-wordpress/manifests/db.pp

mkdir ~/MyModules/do-wordpress/files
cd ~/MyModules/do-wordpress/files

wget http://wordpress.org/latest.tar.gz

mkdir ~/MyModules/do-wordpress/templates
cd /tmp
tar -xvzf ~/MyModules/do-wordpress/files/latest.tar.gz
cp /tmp/wordpress/wp-config-sample.php ~/MyModules/do-wordpress/templates/wp-config.php.erb
rm -rf /tmp/wordpress

echo "
<?php
define('DB_NAME', '<%= scope.lookupvar('wordpress::conf::db_name') %>');
define('DB_USER', '<%= scope.lookupvar('wordpress::conf::db_user') %>');
define('DB_PASSWORD', '<%= scope.lookupvar('wordpress::conf::db_user_password') %>');
define('DB_HOST', '<%= scope.lookupvar('wordpress::conf::db_host') %>');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');

define('AUTH_KEY',         'put your unique phrase here');
define('SECURE_AUTH_KEY',  'put your unique phrase here');
define('LOGGED_IN_KEY',    'put your unique phrase here');
define('NONCE_KEY',        'put your unique phrase here');
define('AUTH_SALT',        'put your unique phrase here');
define('SECURE_AUTH_SALT', 'put your unique phrase here');
define('LOGGED_IN_SALT',   'put your unique phrase here');
define('NONCE_SALT',       'put your unique phrase here');

$table_prefix  = 'wp_';

define('WP_DEBUG', false);

if ( !defined('ABSPATH') )
    define('ABSPATH', dirname(__FILE__) . '/');

require_once(ABSPATH . 'wp-settings.php');
" > ~/MyModules/do-wordpress/templates/wp-config.php.erb

echo "
class wordpress::wp {

    # Copy the Wordpress bundle to /tmp
    file { '/tmp/latest.tar.gz':
        ensure => present,
        source => "puppet:///modules/wordpress/latest.tar.gz"
    }

    # Extract the Wordpress bundle
    exec { 'extract':
        cwd => "/tmp",
        command => "tar -xvzf latest.tar.gz",
        require => File['/tmp/latest.tar.gz'],
        path => ['/bin'],
    }

    # Copy to /var/www/
    exec { 'copy':
        command => "cp -r /tmp/wordpress/* /var/www/",
        require => Exec['extract'],
        path => ['/bin'],
    }

    # Generate the wp-config.php file using the template
    file { '/var/www/wp-config.php':
        ensure => present,
        require => Exec['copy'],
        content => template("wordpress/wp-config.php.erb")
    }
}
" > ~/MyModules/do-wordpress/manifests/wp.pp

echo "
class wordpress {
    # Load all variables
    class { 'wordpress::conf': }

    # Install Apache and PHP
    class { 'wordpress::web': }

    # Install MySQL
    class { 'wordpress::db': }

    # Run Wordpress installation only after Apache is installed
    class { 'wordpress::wp': 
        require => Notify['Apache Installation Complete']
    }

    # Display this message after MySQL installation is complete
    notify { 'MySQL Installation Complete':
        require => Class['wordpress::db']
    }

    # Display this message after Apache installation is complete
    notify { 'Apache Installation Complete':
        require => Class['wordpress::web']
    }

    # Display this message after Wordpress installation is complete
    notify { 'Wordpress Installation Complete':
        require => Class['wordpress::wp']
    }
}
" > ~/MyModules/do-wordpress/manifests/init.pp

cd ~/MyModules
sudo puppet module build do-wordpress
sudo puppet module install ~/MyModules/do-wordpress/pkg/do-wordpress-0.1.0.tar.gz
sudo puppet module uninstall do-wordpress

echo "
class { 'wordpress':
}
" > /tmp/install-wp.pp

sudo puppet apply /tmp/install-wp.pp

