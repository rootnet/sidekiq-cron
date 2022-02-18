require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end

# Always show deprecations unless we want them silenced. Use the env variable
# HIDE_DEPRECATIONS=1 to hide them during testing.
if Warning.respond_to?(:[]=)
  Warning[:deprecated] = !ENV['HIDE_DEPRECATIONS']
end

require 'simplecov'
SimpleCov.start do
  add_filter "/test/"

  add_group 'SidekiqCron', 'lib/'
end

# Use a different reporter for CI runs
require 'minitest/reporters'
Minitest::Reporters.use!(
  if ENV['CI']
    [
      Minitest::Reporters::DefaultReporter.new(color: false, slow_count: 5),
      Minitest::Reporters::JUnitReporter.new('tmp', true, single_file: true),
    ]
  else
    Minitest::Reporters::ProgressReporter.new(color: true, slow_count: 5)
  end,
)

require "minitest/autorun"
require 'shoulda-context'
require "rack/test"
require 'mocha/minitest'

$TESTING = true
ENV['RACK_ENV'] = 'test'

#SIDEKIQ Require - need to have sidekiq running!
require 'sidekiq'
require 'sidekiq/util'
require 'sidekiq/web'

Sidekiq.logger.level = Logger::ERROR

require 'sidekiq/redis_connection'
redis_url = ENV['REDIS_URL'] || 'redis://0.0.0.0:6379'
REDIS = Sidekiq::RedisConnection.create(:url => redis_url)

Sidekiq.configure_client do |config|
  config.redis = { :url => redis_url }
end


$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'sidekiq-cron'
require 'sidekiq/cron/web'
require 'pp'

class CronTestClass
  include Sidekiq::Worker
  sidekiq_options retry: true

  def perform args = {}
    puts "super croned job #{args}"
  end
end

class CronTestClassWithQueue
  include Sidekiq::Worker
  sidekiq_options queue: :super, retry: false, backtrace: true

  def perform args = {}
    puts "super croned job #{args}"
  end
end

module ActiveJob
  class Base
    attr_accessor *%i[job_class provider_job_id queue_name arguments]

    def initialize
      yield self if block_given?
      self.provider_job_id ||= SecureRandom.hex(12)
    end

    def self.queue_name_prefix
      @queue_name_prefix
    end

    def self.queue_name_prefix=(queue_name_prefix)
      @queue_name_prefix = queue_name_prefix
    end

    def self.set(options)
      @queue = options['queue']

      self
    end

    def try(method, *args, &block)
      send method, *args, &block if respond_to? method
    end

    def self.perform_later(*args)
      new do |instance|
        instance.job_class = self.class.name
        instance.queue_name = @queue
        instance.arguments = [*args]
      end
    end
  end
end

class ActiveJobCronTestClass < ActiveJob::Base
end
