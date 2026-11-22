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

class ReminderTest < ActiveSupport::TestCase
  include QboTicketsTestHelper

  SHOP = { 'shop_name' => 'Example Offroad', 'shop_address' => "123 Main St\r\n\r\nAnytown, RI 02800",
           'shop_phone' => '(401) 555-0199', 'shop_website' => 'example.com' }.freeze

  def setup
    User.current = User.find(2)
    allow(:view_customer_appointments)
    @customer = create_customer
    @appointment = create_appointment(customer: @customer, estimate: create_estimate(@customer))
  end

  def reminder
    RedmineQboTickets::Reminder.find(@appointment.id)
  end

  def test_the_shop_from_the_settings
    assert_equal({ name: '', lines: [] }, reminder.shop)
    with_ticket_settings(SHOP) do
      assert_equal({ name: 'Example Offroad', lines: ['123 Main St', 'Anytown, RI 02800', '(401) 555-0199', 'example.com'] },
                   reminder.shop)
    end
  end

  def test_when_they_are_due
    assert_equal({ day: 'Monday', date: 'November 23, 2026', time: '8:30 AM' }, reminder.due)
  end

  def test_details_leave_out_what_only_the_shop_needs
    details = reminder.details.to_h
    assert_equal 'Jane Q Smith', details['Customer']
    assert_equal 'Lift kit install', details['Job']
    assert_equal 'E1068', details['Estimate']
    assert_nil details['Plan on']
    %w[Phone Tech Work\ order].each { |label| assert_not details.key?(label), label }

    @appointment.update_columns(duration: 3)
    assert_equal '3 days', reminder.details.to_h['Plan on']
  end

  def test_other_plugins_add_details_knowing_it_is_a_reminder
    Redmine::Hook.expects(:call_hook).with(:qbo_tickets_details, has_entry(kind: 'reminder'))
                 .returns([[['Vehicle', '2019 Jeep']]])
    assert_equal ['Vehicle', '2019 Jeep'], reminder.details[1]
  end

  def test_notes_only_when_the_settings_say_so
    assert_equal [], reminder.notes
    with_ticket_settings('reminder_notes' => '1') do
      assert_equal [{ t: 'Customer hears a clunk over bumps' }], reminder.notes.first[:runs]
    end
  end

  def test_the_qr_code_adds_it_to_the_calendar
    with_ticket_settings(SHOP) do
      qr = reminder.qr
      assert_equal 'Scan to add it to your calendar', qr[:caption]
      lines = qr[:text].split("\n")
      assert_equal 'BEGIN:VEVENT', lines.first
      assert_equal 'END:VEVENT', lines.last
      assert_includes lines, 'SUMMARY:Example Offroad: Lift kit install'
      assert_includes lines, "DTSTART:#{@appointment.date.utc.strftime('%Y%m%dT%H%M%SZ')}"
      assert_includes lines, "DTEND:#{(@appointment.date + 30.minutes).utc.strftime('%Y%m%dT%H%M%SZ')}"
      assert_includes lines, 'LOCATION:123 Main St\, Anytown\, RI 02800'
      assert_includes lines, 'DESCRIPTION:(401) 555-0199'
    end
  end

  def test_the_qr_code_can_open_the_website_or_be_left_off
    with_ticket_settings(SHOP.merge('reminder_qr' => 'website')) do
      assert_equal 'https://example.com', reminder.qr[:text]
    end
    with_ticket_settings('reminder_qr' => 'website') { assert_nil reminder.qr }
    with_ticket_settings('reminder_qr' => 'none') { assert_nil reminder.qr }
    with_ticket_settings('reminder_qr' => 'bogus') { assert_equal 'calendar', RedmineQboTickets::Settings.reminder_qr }
  end

  def test_call_outs_have_no_reminder
    call_out = CustomerAppointment.create!(event_type: CustomerAppointment::CALL_OUT, user_id: 2, duration: 1,
                                           date: Time.zone.local(2026, 11, 23, 8))
    assert_nil RedmineQboTickets::Reminder.find(call_out.id)
  end

  def test_the_logo_must_be_a_png_the_paper_fits
    logo = "data:image/png;base64,#{Base64.strict_encode64(png(width: 300, height: 100))}"
    with_ticket_settings('logo' => logo) { assert_equal logo, RedmineQboTickets::Settings.logo }
    wide = "data:image/png;base64,#{Base64.strict_encode64(png(width: 576, height: 100))}"
    with_ticket_settings('logo' => wide) { assert_nil RedmineQboTickets::Settings.logo }
    with_ticket_settings('logo' => 'data:image/png;base64,bm90IGEgcG5n') { assert_nil RedmineQboTickets::Settings.logo }
    with_ticket_settings('logo' => 'javascript:alert(1)') { assert_nil RedmineQboTickets::Settings.logo }
  end

  def test_as_json_has_what_the_dialog_draws
    json = reminder.as_json
    assert_equal 'reminder', json[:kind]
    assert_equal %i[kind logo shop due details notes message qr labels].sort, json.keys.sort
    assert_equal 'Please call us if you need to reschedule.', json[:message]
    assert_equal 'APPOINTMENT REMINDER', json[:labels][:heading]
    assert_equal "Reminder: Jane Q Smith (appointment ##{@appointment.id})", reminder.title
  end
end
