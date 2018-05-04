# frozen_string_literal: true

require 'sinatra'

require 'json'
require 'yaml'
require 'securerandom'
require 'base64'
require 'net/http'
require 'uri'
require 'erb'

require_relative 'k8s'
require_relative 'workshops'