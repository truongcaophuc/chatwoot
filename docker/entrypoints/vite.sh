#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

pnpm store prune
pnpm install --force

echo "Ready to run Vite development server."

# Ensure Ruby gems are installed for vite_ruby and other rack dependencies
bundle install --gemfile /app/Gemfile

BUNDLE="bundle check"
until $BUNDLE
do
  sleep 2;
done

exec "$@"
