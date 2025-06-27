#!/usr/bin/env ruby

require 'rubygems'
require 'bundler'

Bundler.require

# Load environment variables
require 'dotenv'
Dotenv.load

# Set environment
ENV['RACK_ENV'] ||= 'production'

# Load the application
require_relative 'app'

# Run the application
run KeaDhcpApp
