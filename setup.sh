#!/bin/bash

# Define variables
drupal_version="^10.2"
lando_yml_file=".lando.yml"
env_file=".lando.env"
settings_file="web/sites/default/settings.php"

# Remove existing setup files
rm -rf vendor .lando.yml .lando.env tmp composer.*

# Generate .lando.yml
cat <<EOF >> "$lando_yml_file"
name: drupal
recipe: drupal10
config:
  php: "8.2"
  via: nginx
  webroot: web
  database: "mariadb:10.6"
  xdebug: off

services:
  appserver:
    build:
      - "composer install"
    overrides:
      environment:
        ENVIRONMENT_NAME=lando

env_file:
  - .lando.env
EOF

# Generate .lando.env
cat <<EOF >> "$env_file"
DRUSH_OPTIONS_URI=https://drupal.lndo.site
EOF

# Create project using Composer
lando composer create-project drupal/recommended-project:"$drupal_version" --no-install tmp && cp -r tmp/. . && rm -rf tmp

# Remove Drupal core project messages
lando composer remove drupal/core-project-message --no-update
lando composer config --unset allow-plugins.drupal/core-project-message
lando composer config --unset extra.drupal-core-project-message

# Install Drush
lando composer require drush/drush

# Check if settings.php file exists
if [ -f "$settings_file" ]; then
    # Change permissions
    chmod +w "$settings_file"
    # Remove settings.php
    rm -f "$settings_file"
fi

# Create and configure settings.php
touch "$settings_file"

cat <<EOF >> "$settings_file"
<?php

/**
 * @file
 * Drupal site-specific configuration file.
 */

// Database settings with Lando defaults.
\$databases['default']['default'] = [
  'database' => empty(getenv('DB_NAME')) ? 'drupal10' : getenv('DB_NAME'),
  'username' => empty(getenv('DB_USER')) ? 'drupal10' : getenv('DB_USER'),
  'password' => empty(getenv('DB_PASS')) ? 'drupal10' : getenv('DB_PASS'),
  'host' => empty(getenv('DB_HOST')) ? 'database' : getenv('DB_HOST'),
  'port' => empty(getenv('DB_PORT')) ? '3306' : getenv('DB_PORT'),
  'prefix' => '',
  'driver' => 'mysql',
];

// Salt for one-time login links, cancel links, form tokens, etc.
\$settings['hash_salt'] = empty(getenv('HASH_SALT')) ? 'notsosecurehash' : getenv('HASH_SALT');

// Public files path.
\$settings['file_public_path']  = 'sites/default/files';

// Location of the site configuration files.
\$settings['config_sync_directory'] = '../config/sync';

// Conditional settings for Lando environment.
if (getenv('ENVIRONMENT_NAME') === 'lando') {
    \$settings['trusted_host_patterns'] = ['.*'];
}
EOF

chmod 644 "$settings_file"

# Rebuild Lando environment
lando rebuild -y

# Install Drupal site with standard profile
lando drush site:install standard -y

# Run cron
lando drush core:cron

# Clear cache
lando drush cache:rebuild

# Get one-time login link
lando drush user:login
