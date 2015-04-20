#!/usr/bin/env ruby
$:.unshift File.expand_path('../../lib', __FILE__)

require 'bundler/setup'

require 'test/unit'
require 'mocha/test_unit'

require 'yaml'
require 'json'
require 'active_merchant'
require 'comm_stub'

require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/time/acts_like'

ActiveMerchant::Billing::Base.mode = :test

if ENV['DEBUG_ACTIVE_MERCHANT'] == 'true'
  require 'logger'
  ActiveMerchant::Billing::Gateway.logger = Logger.new(STDOUT)
  ActiveMerchant::Billing::Gateway.wiredump_device = STDOUT
end

# Test gateways
class SimpleTestGateway < ActiveMerchant::Billing::Gateway
end

class SubclassGateway < SimpleTestGateway
end

module ActiveMerchant
  module Assertions
    AssertionClass = defined?(Minitest) ? MiniTest::Assertion : Test::Unit::AssertionFailedError

    def assert_field(field, value)
      clean_backtrace do
        assert_equal value, @helper.fields[field]
      end
    end

    # Allows testing of negative assertions:
    #
    #   # Instead of
    #   assert !something_that_is_false
    #
    #   # Do this
    #   assert_false something_that_should_be_false
    #
    # An optional +msg+ parameter is available to help you debug.
    def assert_false(boolean, message = nil)
      message = build_message message, '<?> is not false or nil.', boolean

      clean_backtrace do
        assert_block message do
          not boolean
        end
      end
    end

    # An assertion of a successful response:
    #
    #   # Instead of
    #   assert response.success?
    #
    #   # DRY that up with
    #   assert_success response
    #
    # A message will automatically show the inspection of the response
    # object if things go afoul.
    def assert_success(response, message=nil)
      clean_backtrace do
        assert response.success?, build_message(nil, "#{message + "\n" if message}Response expected to succeed: <?>", response)
      end
    end

    # The negative of +assert_success+
    def assert_failure(response, message=nil)
      clean_backtrace do
        assert !response.success?, build_message(nil, "#{message + "\n" if message}Response expected to fail: <?>", response)
      end
    end

    def assert_valid(model, message=nil)
      errors = model.validate

      clean_backtrace do
        assert_equal({}, errors, (message || "Expected to be valid"))
      end

      errors
    end

    def assert_not_valid(model)
      errors = model.validate

      clean_backtrace do
        assert_not_equal({}, errors, "Expected to not be valid")
      end

      errors
    end

    def assert_deprecation_warning(message=nil)
      ActiveMerchant.expects(:deprecated).with(message ? message : anything)
      yield
    end

    def refute(value, message = nil)
      assert(!value, message)
    end

    def silence_deprecation_warnings
      ActiveMerchant.stubs(:deprecated)
      yield
    end

    def assert_no_deprecation_warning
      ActiveMerchant.expects(:deprecated).never
      yield
    end

    def assert_scrubbed(unexpected_value, transcript)
      refute transcript.include?(unexpected_value), "Expected #{unexpected_value} to be scrubbed out of transcript"
    end

    private
    def clean_backtrace(&block)
      yield
    rescue AssertionClass => e
      path = File.expand_path(__FILE__)
      raise AssertionClass, e.message, e.backtrace.reject { |line| File.expand_path(line) =~ /#{path}/ }
    end
  end

  module Fixtures
    HOME_DIR = RUBY_PLATFORM =~ /mswin32/ ? ENV['HOMEPATH'] : ENV['HOME'] unless defined?(HOME_DIR)
    LOCAL_CREDENTIALS = File.join(HOME_DIR.to_s, '.active_merchant/fixtures.yml') unless defined?(LOCAL_CREDENTIALS)
    DEFAULT_CREDENTIALS = File.join(File.dirname(__FILE__), 'fixtures.yml') unless defined?(DEFAULT_CREDENTIALS)

    private
    def default_expiration_date
      @default_expiration_date ||= Date.new((Time.now.year + 1), 9, 30)
    end

    def credit_card(number = '4242424242424242', options = {})
      defaults = {
        :number => number,
        :month => default_expiration_date.month,
        :year => default_expiration_date.year,
        :first_name => 'Longbob',
        :last_name => 'Longsen',
        :verification_value => '123',
        :brand => 'visa'
      }.update(options)

      Billing::CreditCard.new(defaults)
    end

    def credit_card_with_track_data(number = '4242424242424242', options = {})
      defaults = {
        :track_data => '%B' + number + '^LONGSEN/L. ^15121200000000000000**123******?',
      }.update(options)

      Billing::CreditCard.new(defaults)
    end

    def network_tokenization_credit_card(number = '4242424242424242', options = {})
      defaults = {
        :number => number,
        :month => default_expiration_date.month,
        :year => default_expiration_date.year,
        :first_name => 'Longbob',
        :last_name => 'Longsen',
        :verification_value => '123',
        :brand => 'visa'
      }.update(options)

      Billing::NetworkTokenizationCreditCard.new(defaults)
    end

    # this mock is only useful with unit tests, as cryptograms generated by an EMV terminal
    # are specific to the target acquirer, so remote tests using this mock will fail.
    def credit_card_with_icc_data(options = {})
      defaults = {
        icc_data: '500B56495341204352454449545F201A56495341204143515549524552205445535420434152442030315F24031512315F280208405F2A0208265F300202015F34010182025C008407A0000000031010950502000080009A031408259B02E8009C01009F02060000000734499F03060000000000009F0607A00000000310109F0902008C9F100706010A03A080009F120F4352454449544F20444520564953419F1A0208269F1C0831373030303437309F1E0831373030303437309F2608EB2EC0F472BEA0A49F2701809F3303E0B8C89F34031E03009F3501229F360200C39F37040A27296F9F4104000001319F4502DAC5DFAE5711476173FFFFFF0119D15122011758989389DFAE5A08476173FFFFFF011957114761739001010119D151220117589893895A084761739001010119'
      }

      Billing::CreditCard.new(defaults)
    end

    def check(options = {})
      defaults = {
        :name => 'Jim Smith',
        :bank_name => 'Bank of Elbonia',
        :routing_number => '244183602',
        :account_number => '15378535',
        :account_holder_type => 'personal',
        :account_type => 'checking',
        :number => '1'
      }.update(options)

      Billing::Check.new(defaults)
    end

    def apple_pay_payment_token(options = {})
      # apple_pay_json_raw should contain the JSON serialization of the object described here
      # https://developer.apple.com/library/IOs//documentation/PassKit/Reference/PaymentTokenJSON/PaymentTokenJSON.htm
      apple_pay_json_raw = '{"version":"EC_v1","data":"","signature":""}'
      defaults = {
        payment_data: ActiveSupport::JSON.decode(apple_pay_json_raw),
        payment_instrument_name: "Visa 2424",
        payment_network: "Visa",
        transaction_identifier: "uniqueidentifier123"
      }.update(options)

      ActiveMerchant::Billing::ApplePayPaymentToken.new(defaults[:payment_data],
        payment_instrument_name: defaults[:payment_instrument_name],
        payment_network: defaults[:payment_network],
        transaction_identifier: defaults[:transaction_identifier]
      )
    end

    def address(options = {})
      {
        name:     'Jim Smith',
        address1: '456 My Street',
        address2: 'Apt 1',
        company:  'Widgets Inc',
        city:     'Ottawa',
        state:    'ON',
        zip:      'K1C2N6',
        country:  'CA',
        phone:    '(555)555-5555',
        fax:      '(555)555-6666'
      }.update(options)
    end

    def generate_unique_id
      SecureRandom.hex(16)
    end

    def all_fixtures
      @@fixtures ||= load_fixtures
    end

    def fixtures(key)
      data = all_fixtures[key] || raise(StandardError, "No fixture data was found for '#{key}'")

      data.dup
    end

    def load_fixtures
      [DEFAULT_CREDENTIALS, LOCAL_CREDENTIALS].inject({}) do |credentials, file_name|
        if File.exist?(file_name)
          yaml_data = YAML.load(File.read(file_name))
          credentials.merge!(symbolize_keys(yaml_data))
        end
        credentials
      end
    end

    def symbolize_keys(hash)
      return unless hash.is_a?(Hash)

      hash.symbolize_keys!
      hash.each{|k,v| symbolize_keys(v)}
    end
  end
end

Test::Unit::TestCase.class_eval do
  include ActiveMerchant::Billing
  include ActiveMerchant::Assertions
  include ActiveMerchant::Fixtures

  def capture_transcript(gateway)
    transcript = ''
    gateway.class.wiredump_device = transcript

    yield

    transcript
  end

  def dump_transcript_and_fail(gateway, amount, credit_card, params)
    transcript = capture_transcript(gateway) do
      gateway.purchase(amount, credit_card, params)
    end

    File.open("transcript.log", "w") { |f| f.write(transcript) }
    assert false, "A purchase transcript has been written to transcript.log for you to test scrubbing with."
  end
end

module ActionViewHelperTestHelper
  def self.included(base)
    base.send(:include, ActiveMerchant::Billing::Integrations::ActionViewHelper)
    base.send(:include, ActionView::Helpers::FormHelper)
    base.send(:include, ActionView::Helpers::FormTagHelper)
    base.send(:include, ActionView::Helpers::UrlHelper)
    base.send(:include, ActionView::Helpers::TagHelper)
    base.send(:include, ActionView::Helpers::CaptureHelper)
    base.send(:include, ActionView::Helpers::TextHelper)
    base.send(:attr_accessor, :output_buffer)
  end

  def setup
    @controller = Class.new do
      attr_reader :url_for_options
      def url_for(options, *parameters_for_method_reference)
        @url_for_options = options
      end
    end
    @controller = @controller.new
    @output_buffer = ''
  end

  protected
  def protect_against_forgery?
    false
  end
end
