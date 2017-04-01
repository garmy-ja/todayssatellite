#!/usr/bin/env ruby

require 'pathname'
require 'rubygems'
require 'daemons'

begin
  Daemons.run('satellite_tweet_bot.rb')
rescue => e
  p e.class
  p e.message
  p e.backtrace
end
