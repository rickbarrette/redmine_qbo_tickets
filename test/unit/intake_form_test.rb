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

class IntakeFormTest < ActiveSupport::TestCase
  include QboTicketsTestHelper

  def setup
    User.current = User.find(2)
    allow(:view_customers)
    @customer = create_customer
  end

  def form(params = {})
    RedmineQboTickets::IntakeForm.find(@customer.id, params)
  end

  def test_it_needs_a_customer_the_user_may_see
    assert form
    assert_nil RedmineQboTickets::IntakeForm.find(0)
    Role.find(1).remove_permission!(:view_customers)
    User.current = User.find(2)
    assert_nil form
  end

  def test_the_top_names_the_customer
    assert_equal 'SMITH', form.name
    assert_equal 'Vehicle intake', form.as_json[:number]
    assert_nil form.as_json[:when]
    with_ticket_settings('uppercase' => '0') { assert_equal 'Smith', form.name }
  end

  def test_details
    RedmineQboTickets.stubs(:hook_list).returns([])
    assert_equal [['Customer', 'Jane Q Smith'], ['Phone', '(401) 555-0100']], form.details
  end

  def test_the_intake_fields_are_blank
    field = bool_field('Check Engine Light')
    with_ticket_settings('custom_field_ids' => [field.id.to_s]) do
      assert_equal [{ name: 'Check Engine Light', kind: 'yesno', value: '', choices: [] }], form.fields
    end
  end

  def test_the_hooks_get_the_customer_and_the_links_params
    RedmineQboTickets.expects(:hook_list)
                     .with(:qbo_tickets_details, has_entries(kind: 'intake', customer: @customer,
                                                             params: { 'vehicle_id' => '12' }, appointment: nil))
                     .returns([['Vehicle', '2019 Jeep Wrangler'], 'not a line'])
    assert_includes form('vehicle_id' => '12').details, ['Vehicle', '2019 Jeep Wrangler']
  end

  def test_the_qr_code_opens_the_customer_without_a_listener
    RedmineQboTickets.stubs(:hook_first).returns(nil)
    qr = form.qr
    assert_equal "#{RedmineQboTickets::Ticket.base_url}/customers/#{@customer.id}", qr[:url]
    assert_equal 'Scan to open the customer', qr[:caption]

    RedmineQboTickets.stubs(:hook_first).returns(url: 'https://redmine.example.com/vehicles/12', caption: 'Open it')
    assert_equal({ url: 'https://redmine.example.com/vehicles/12', caption: 'Open it' }, form.qr)
  end

  def test_the_links_other_params_are_kept
    params = ActionController::Parameters.new(
      controller: 'intake_tickets', action: 'new', customer_id: '9701', vehicle_id: '12', estimate_id: '',
      image: 'data:...', copies: '2', 'Bad-Key' => '1', nested: { a: '1' }, list: ['1']
    )
    assert_equal({ 'vehicle_id' => '12' }, RedmineQboTickets::IntakeForm.extra_params(params))
    found = RedmineQboTickets::IntakeForm.from_params(params.merge(customer_id: @customer.id.to_s))
    assert_equal({ 'vehicle_id' => '12', 'customer_id' => @customer.id }, found.dialog_params)
  end

  def test_as_json
    json = form.as_json
    assert_equal 'intake', json[:kind]
    assert_equal [], json[:notes]
    assert_nil json[:job]
    assert_equal 5, json[:note_lines]
    assert_equal 'INTAKE NOTES', json[:labels][:intake_notes]
    assert_equal 'Intake form: SMITH', form.title
    assert_equal 'customer', RedmineQboTickets::IntakeForm::SOURCE_TYPE
    assert_equal @customer.id, form.source_id
  end
end
