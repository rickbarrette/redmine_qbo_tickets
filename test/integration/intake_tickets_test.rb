#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.expand_path('../test_helper', __dir__)

class IntakeTicketsTest < Redmine::IntegrationTest
  include QboTicketsTestHelper

  def setup
    @printer = create_receipt_printer
    allow(:print_key_tickets, :view_customers)
    @customer = create_customer
  end

  def test_the_customer_page_has_print_intake_form
    log_user('jsmith', 'jsmith')
    get "/customers/#{@customer.id}"
    assert_response :success
    # What's ticked on the page (e.g. a vehicle) is added to it by redmine_qbo's data-ticked-params
    assert_select "a.qbo-ticket-intake-link[href=?][data-ticked-params='%s'][data-remote=true]",
                  "/intake_tickets/new?customer_id=#{@customer.id}"
    assert_match(/qbo_tickets[^"]*\.js/, response.body)
    assert_match(/qrcode[^"]*\.js/, response.body)
  end

  def test_no_link_without_the_permission_or_a_receipt_printer
    log_user('jsmith', 'jsmith')
    Role.find(1).remove_permission!(:print_key_tickets)
    get "/customers/#{@customer.id}"
    assert_select 'a.qbo-ticket-intake-link', 0
    refute_match(/qbo_tickets[^"]*\.js/, response.body)

    allow(:print_key_tickets)
    @printer.update!(active: false)
    get "/customers/#{@customer.id}"
    assert_select 'a.qbo-ticket-intake-link', 0
  end

  def test_the_dialog_has_the_form_and_keeps_the_links_params
    log_user('jsmith', 'jsmith')
    get '/intake_tickets/new', params: { customer_id: @customer.id, vehicle_id: '12' }, xhr: true
    assert_response :success
    assert_includes response.body, '"kind":"intake"'
    assert_includes response.body, '"name":"SMITH"'
    assert_includes response.body, 'Print intake form'
    params = response.body[/data-params=\\"([^"\\]*)\\"/, 1]
    assert_equal({ 'vehicle_id' => '12', 'customer_id' => @customer.id }, JSON.parse(CGI.unescapeHTML(params)))
  end

  def test_the_dialog_needs_the_permissions
    log_user('jsmith', 'jsmith')
    get '/intake_tickets/new', params: { customer_id: 0 }, xhr: true
    assert_response :not_found

    Role.find(1).remove_permission!(:view_customers)
    get '/intake_tickets/new', params: { customer_id: @customer.id }, xhr: true
    assert_response :not_found

    reset!
    log_user('dlopper', 'foo')
    get '/intake_tickets/new', params: { customer_id: @customer.id }, xhr: true
    assert_response :forbidden
  end

  def test_print_queues_the_picture_for_the_customer
    log_user('jsmith', 'jsmith')
    assert_difference 'LabelJob.count', 1 do
      post '/intake_tickets', params: { customer_id: @customer.id, vehicle_id: '12', image: Base64.strict_encode64(png) },
                              xhr: true
    end
    assert_response :success
    job = LabelJob.last
    assert_equal png, job.image
    assert_equal 'customer', job.source_type
    assert_equal @customer.id.to_s, job.source_id
    assert_equal 'Intake form: SMITH', job.title
    assert_equal "/intake_tickets/#{job.id}", response.parsed_body['url']

    get "/intake_tickets/#{job.id}", headers: { 'Accept' => 'application/json' }
    assert_response :success
    assert_equal 'queued', response.parsed_body['status']
    # An appointment's dialog doesn't follow a customer's print job
    get "/key_tickets/#{job.id}", headers: { 'Accept' => 'application/json' }
    assert_response :not_found
  end
end
