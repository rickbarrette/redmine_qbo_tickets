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

class TicketTest < ActiveSupport::TestCase
  include QboTicketsTestHelper

  def setup
    User.current = User.find(2)
    allow(:view_customer_appointments)
    @customer = create_customer
    @appointment = create_appointment(customer: @customer, estimate: create_estimate(@customer))
  end

  def ticket
    RedmineQboTickets::Ticket.find(@appointment.id)
  end

  def test_the_top_names_the_customer_and_when_they_are_due
    assert_equal 'SMITH', ticket.name
    assert_equal 'Mon 11/23/2026 · 8:30 AM', ticket.when_text
    assert_equal 'Appointment #' + @appointment.id.to_s, ticket.number
  end

  def test_capitals_can_be_turned_off
    with_ticket_settings('uppercase' => '0') { assert_equal 'Smith', ticket.name }
  end

  def test_without_a_customer_the_subject_names_it
    @appointment.update_columns(customer_id: nil)
    assert_equal 'LIFT KIT INSTALL', ticket.name
  end

  def test_details
    details = ticket.details.to_h
    assert_equal 'Jane Q Smith', details['Customer']
    assert_equal '(401) 555-0100', details['Phone']
    assert_equal 'E1068', details['Estimate']
    assert_equal 'John Smith', details['Tech']
    assert_nil details['Work order']
    assert_equal 'Lift kit install', ticket.job
    assert_equal 'Customer hears a clunk over bumps', ticket.notes_text
  end

  def test_notes_text
    @appointment.update_columns(description: "Replaced everything.\r\n\r\nsee ##16262, not #3")
    assert_equal "Replaced everything.\n\nsee W16262, not #3", ticket.notes_text
    @appointment.update_columns(description: 'x' * 1200)
    assert_equal 1000, ticket.notes_text.length
    @appointment.update_columns(description: '')
    assert_equal [], ticket.notes
  end

  def test_notes_are_formatted
    Setting.stubs(:text_formatting).returns('common_mark')
    @appointment.update_columns(description: "Customer reported **death** wobble\n\n> [!important]\n> check steering")
    blocks = ticket.notes
    assert_equal [{ t: 'Customer reported ' }, { b: true, t: 'death' }, { t: ' wobble' }], blocks[0][:runs]
    assert_equal 'alert', blocks[1][:type]
    assert_equal [{ t: 'IMPORTANT' }], blocks[1][:runs]
    assert_equal({ type: 'p', quote: 1, runs: [{ t: 'check steering' }] }, blocks[2])
  end

  def test_the_work_order_once_there_is_one
    link_issue(@appointment, Issue.find(1))
    assert_equal 'W1', ticket.details.to_h['Work order']
  end

  def test_phone_numbers
    assert_equal '(401) 555-0100', RedmineQboTickets::Ticket.phone('14015550100')
    assert_equal '555-0100', RedmineQboTickets::Ticket.phone('555-0100')
  end

  def test_call_outs_and_unseen_appointments_have_no_ticket
    call_out = CustomerAppointment.create!(event_type: CustomerAppointment::CALL_OUT, user_id: 2, duration: 1,
                                           date: Time.zone.local(2026, 11, 23, 8))
    assert_nil RedmineQboTickets::Ticket.find(call_out.id)
    Role.find(1).remove_permission!(:view_customer_appointments)
    User.current = User.find(2)
    assert_nil RedmineQboTickets::Ticket.find(@appointment.id)
  end

  def test_fields_print_by_their_format
    cel = bool_field('Check Engine Light')
    mileage = IssueCustomField.create!(name: 'Mileage', field_format: 'int', is_for_all: true, tracker_ids: Tracker.ids)
    fuel = IssueCustomField.create!(name: 'Fuel', field_format: 'list', possible_values: %w[E 1/4 1/2 3/4 F],
                                    is_for_all: true, tracker_ids: Tracker.ids)
    many = IssueCustomField.create!(name: 'Color', field_format: 'list', possible_values: %w[A B C D E F G],
                                    is_for_all: true, tracker_ids: Tracker.ids)
    unchosen = bool_field('Save Parts')
    with_ticket_settings('custom_field_ids' => [cel, mileage, fuel, many].map(&:id).map(&:to_s)) do
      fields = ticket.fields.index_by { |field| field[:name] }
      assert_equal %w[Check\ Engine\ Light Mileage Fuel Color], fields.keys
      assert_equal 'yesno', fields['Check Engine Light'][:kind]
      assert_equal '', fields['Check Engine Light'][:value]
      assert_equal 'line', fields['Mileage'][:kind]
      assert_equal 'choices', fields['Fuel'][:kind]
      assert_equal %w[E 1/4 1/2 3/4 F], fields['Fuel'][:choices]
      assert_equal 'line', fields['Color'][:kind]
      assert_not fields.key?(unchosen.name)
    end
  end

  def test_fields_show_the_work_orders_values
    cel = bool_field('Check Engine Light')
    mileage = IssueCustomField.create!(name: 'Mileage', field_format: 'int', is_for_all: true, tracker_ids: Tracker.ids)
    issue = Issue.find(1)
    issue.custom_field_values = { cel.id.to_s => '1', mileage.id.to_s => '84210' }
    issue.save!
    link_issue(@appointment, issue)
    with_ticket_settings('custom_field_ids' => [cel.id.to_s, mileage.id.to_s]) do
      fields = ticket.fields.index_by { |field| field[:name] }
      assert_equal '1', fields['Check Engine Light'][:value]
      assert_equal '84210', fields['Mileage'][:value]
    end
  end

  def test_qr_code_opens_the_appointment_without_other_plugins
    Redmine::Hook.stubs(:call_hook).returns([])
    qr = ticket.qr
    assert_equal "#{RedmineQboTickets::Ticket.base_url}/customer_appointments/#{@appointment.id}", qr[:url]
    assert_equal 'Scan to open the appointment', qr[:caption]
  end

  def test_other_plugins_add_details_and_the_qr_code
    Redmine::Hook.stubs(:call_hook).with(:qbo_tickets_details, anything).returns([[['Vehicle', '2019 Jeep']]])
    Redmine::Hook.stubs(:call_hook).with(:qbo_tickets_qr, anything).returns([{}, { url: 'https://x/v/1', caption: 'Scan me' }])
    assert_equal ['Vehicle', '2019 Jeep'], ticket.details[2]
    assert_equal({ url: 'https://x/v/1', caption: 'Scan me' }, ticket.qr)
  end

  def test_as_json_has_what_the_dialog_draws
    json = ticket.as_json
    assert_equal %i[name when number details job notes fields note_lines qr labels].sort, json.keys.sort
    assert_equal 5, json[:note_lines]
    assert_equal 'Yes', json[:labels][:yes]
    assert_equal 'Printed %{time}', json[:labels][:printed]
    assert_match 'SMITH', ticket.title
  end
end
