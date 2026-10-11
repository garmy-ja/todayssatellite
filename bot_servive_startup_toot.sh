#!/bin/bash
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"
bundle exec ruby satellite_toot_bot.rb
