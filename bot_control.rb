#!/usr/bin/env ruby

require 'rubygems'
require 'daemons'

# Resolve the bot script relative to this controller, not the caller's cwd.
# Daemons keeps its normal start/stop/restart/run command behavior.
bot_script = File.expand_path('satellite_tweet_bot.rb', __dir__)
Daemons.run(bot_script)
