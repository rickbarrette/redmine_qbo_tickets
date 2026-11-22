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

class KeyTicketsTest < Redmine::IntegrationTest
  include QboTicketsTestHelper

  def setup
    @printer = create_receipt_printer
    allow(:print_key_tickets, :view_customer_appointments)
    @customer = create_customer
    @appointment = create_appointment(customer: @customer)
  end

  def test_the_appointment_page_has_print_key_ticket
    log_user('jsmith', 'jsmith')
    get "/customer_appointments/#{@appointment.id}"
    assert_response :success
    assert_select "a.qbo-ticket-print-link[href=?]", "/key_tickets/new?appointment_id=#{@appointment.id}"
    assert_match(/qbo_tickets[^"]*\.js/, response.body)
    assert_match(/qrcode[^"]*\.js/, response.body)
  end

  def test_no_link_without_a_receipt_printer_or_the_permission
    log_user('jsmith', 'jsmith')
    @printer.update!(active: false)
    get "/customer_appointments/#{@appointment.id}"
    assert_select 'a.qbo-ticket-print-link', 0

    @printer.update!(active: true)
    Role.find(1).remove_permission!(:print_key_tickets)
    get "/customer_appointments/#{@appointment.id}"
    assert_select 'a.qbo-ticket-print-link', 0
  end

  def test_a_label_printer_is_not_a_receipt_printer
    @printer.update!(kind: 'label')
    log_user('jsmith', 'jsmith')
    get "/customer_appointments/#{@appointment.id}"
    assert_select 'a.qbo-ticket-print-link', 0
  end

  def test_the_dialog_has_the_ticket
    log_user('jsmith', 'jsmith')
    get '/key_tickets/new', params: { appointment_id: @appointment.id }, xhr: true
    assert_response :success
    assert_includes response.body, 'qbo-ticket-preview'
    assert_includes response.body, 'QboTickets.initDialog'
    assert_includes response.body, '"name":"SMITH"'
  end

  def test_the_dialog_needs_the_permission_and_a_visible_appointment
    log_user('dlopper', 'foo')
    get '/key_tickets/new', params: { appointment_id: @appointment.id }, xhr: true
    assert_response :forbidden

    reset!
    log_user('jsmith', 'jsmith')
    get '/key_tickets/new', params: { appointment_id: 0 }, xhr: true
    assert_response :not_found
  end

  def test_print_queues_the_picture_on_the_receipt_printer
    log_user('jsmith', 'jsmith')
    image = "data:image/png;base64,#{Base64.strict_encode64(png)}"
    assert_difference 'LabelJob.count', 1 do
      post '/key_tickets', params: { appointment_id: @appointment.id, image: image, copies: '2' }, xhr: true
    end
    assert_response :success
    job = LabelJob.last
    assert_equal @printer, job.label_printer
    assert_equal png, job.image
    assert_equal 2, job.copies
    assert_equal 'appointment', job.source_type
    assert_equal @appointment.id.to_s, job.source_id
    assert_equal "Key ticket: SMITH (appointment ##{@appointment.id})", job.title
    assert_equal "/key_tickets/#{job.id}", response.parsed_body['url']
  end

  def test_a_bad_picture_is_refused
    log_user('jsmith', 'jsmith')
    post '/key_tickets', params: { appointment_id: @appointment.id, image: 'data:image/png;base64,notapng' }, xhr: true
    assert_response :unprocessable_entity
    assert response.parsed_body['errors'].any?
    post '/key_tickets', params: { appointment_id: @appointment.id, image: Base64.strict_encode64(png(width: 300)) }, xhr: true
    assert_response :unprocessable_entity
    assert_equal 0, LabelJob.count
  end

  def test_following_your_own_ticket
    log_user('jsmith', 'jsmith')
    post '/key_tickets', params: { appointment_id: @appointment.id, image: Base64.strict_encode64(png) }, xhr: true
    job = LabelJob.last
    get "/key_tickets/#{job.id}", headers: { 'Accept' => 'application/json' }
    assert_response :success
    assert_equal 'queued', response.parsed_body['status']
    assert_equal false, response.parsed_body['finished']

    job.finish!(printed: true)
    get "/key_tickets/#{job.id}", headers: { 'Accept' => 'application/json' }
    assert_equal 'printed', response.parsed_body['status']

    job.update_columns(user_id: 3)
    get "/key_tickets/#{job.id}", headers: { 'Accept' => 'application/json' }
    assert_response :not_found
  end

  def test_the_appointment_page_has_print_reminder_with_its_permission
    log_user('jsmith', 'jsmith')
    get "/customer_appointments/#{@appointment.id}"
    assert_select 'a.qbo-ticket-reminder-link', 0

    Role.find(1).remove_permission!(:print_key_tickets)
    allow(:print_reminder_tickets)
    get "/customer_appointments/#{@appointment.id}"
    assert_select 'a.qbo-ticket-print-link', 0
    assert_select "a.qbo-ticket-reminder-link[href=?]", "/reminder_tickets/new?appointment_id=#{@appointment.id}"
    assert_match(/qbo_tickets[^"]*\.js/, response.body)
  end

  def test_the_reminder_dialog_and_printing
    allow(:print_reminder_tickets)
    log_user('jsmith', 'jsmith')
    get '/reminder_tickets/new', params: { appointment_id: @appointment.id }, xhr: true
    assert_response :success
    assert_includes response.body, '"kind":"reminder"'
    assert_includes response.body, 'Print reminder'

    post '/reminder_tickets', params: { appointment_id: @appointment.id, image: Base64.strict_encode64(png) }, xhr: true
    assert_response :success
    job = LabelJob.last
    assert_equal "Reminder: Jane Q Smith (appointment ##{@appointment.id})", job.title
    assert_equal "/reminder_tickets/#{job.id}", response.parsed_body['url']
    get "/reminder_tickets/#{job.id}", headers: { 'Accept' => 'application/json' }
    assert_equal 'queued', response.parsed_body['status']
  end

  def test_the_reminder_needs_its_permission
    log_user('jsmith', 'jsmith')
    get '/reminder_tickets/new', params: { appointment_id: @appointment.id }, xhr: true
    assert_response :forbidden
  end

  def test_settings_page
    IssueCustomField.create!(name: 'Check Engine Light', field_format: 'bool', is_for_all: true, tracker_ids: Tracker.ids)
    log_user('admin', 'admin')
    get '/settings/plugin/redmine_qbo_tickets'
    assert_response :success
    assert_includes response.body, 'Check Engine Light'
    assert_includes response.body, 'Yes / No boxes'

    field = IssueCustomField.find_by(name: 'Check Engine Light')
    post '/settings/plugin/redmine_qbo_tickets',
         params: { settings: { custom_field_ids: ['', field.id.to_s], note_lines: '3', uppercase: '1' } }
    assert_equal [field.id], RedmineQboTickets::Settings.custom_field_ids
    assert_equal 3, RedmineQboTickets::Settings.note_lines
  end

  def test_reminder_settings
    log_user('admin', 'admin')
    get '/settings/plugin/redmine_qbo_tickets'
    assert_select 'input[type=file]#qbo_tickets_logo_file'
    assert_match(/qbo_tickets_settings[^"]*\.js/, response.body)

    logo = "data:image/png;base64,#{Base64.strict_encode64(png(width: 400, height: 120))}"
    post '/settings/plugin/redmine_qbo_tickets',
         params: { settings: { logo: logo, shop_name: 'Example Offroad', shop_address: "123 Main St\r\nAnytown",
                               shop_phone: '401-555-0199', shop_website: 'example.com', reminder_message: 'See you soon',
                               reminder_qr: 'website', reminder_notes: '1' } }
    assert_equal logo, RedmineQboTickets::Settings.logo
    assert_equal ['123 Main St', 'Anytown'], RedmineQboTickets::Settings.shop_address_lines
    assert_equal 'website', RedmineQboTickets::Settings.reminder_qr
    assert RedmineQboTickets::Settings.reminder_notes?

    get '/settings/plugin/redmine_qbo_tickets'
    assert_select 'input#settings_logo[value=?]', logo
    assert_select 'input#settings_shop_name[value=?]', 'Example Offroad'
  end
end
