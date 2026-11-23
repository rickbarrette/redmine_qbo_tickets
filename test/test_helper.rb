#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.expand_path('../../../test/test_helper', __dir__)

module QboTicketsTestHelper
  PERMISSIONS = %i[print_key_tickets print_reminder_tickets view_customer_appointments view_customers].freeze

  def self.included(base)
    base.fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
                  :projects_trackers, :issue_statuses, :enabled_modules, :enumerations, :workflows
    base.setup do
      # QuickBooks' copy of customers is never fetched in tests (last names come from their Redmine name)
      RedmineQboLabels::LabelSource.stubs(:qbo_details).returns(nil)
      LabelJob.delete_all
      LabelPrinter.delete_all
      AppointmentEstimateIssue.delete_all
      CustomerAppointment.delete_all
      Customer.where(id: 9700..9799).delete_all
      Estimate.where(id: 9700..9799).delete_all
      Setting.plugin_redmine_qbo_tickets = RedmineQboTickets::Settings::DEFAULTS.dup
      Role.find(1).remove_permission!(*PERMISSIONS)
    end
  end

  # Gives jsmith's Manager role these permissions
  def allow(*permissions)
    role = Role.find(1)
    permissions.each { |permission| role.add_permission!(permission) }
    User.current = User.find(User.current.id) if User.current.logged?
  end

  def create_receipt_printer(name: 'Front desk')
    printer = LabelPrinter.new(name: name, kind: 'receipt')
    printer.generate_token
    printer.save!
    printer
  end

  # A customer, without sending it to QuickBooks
  def create_customer(id: 9701, name: 'Jane Q Smith', phone: '4015550100')
    customer = Customer.new(id: id, name: name, phone_number: phone)
    customer.skip_qbo_push = true
    customer.save!
    customer
  end

  def create_estimate(customer, id: 9701, doc_number: '1068')
    Estimate.create!(id: id, doc_number: doc_number, customer_id: customer.id)
  end

  def create_appointment(**attributes)
    CustomerAppointment.create!({ subject: 'Lift kit install', description: 'Customer hears a clunk over bumps',
                                  date: Time.zone.local(2026, 11, 23, 8, 30), duration: 1, estimated_hours: 4,
                                  user_id: 2, project_id: 1 }.merge(attributes))
  end

  # The appointment's work order (as made from its estimate)
  def link_issue(appointment, issue)
    AppointmentEstimateIssue.create!(customer_appointment: appointment, issue: issue,
                                     estimate_id: appointment.estimate_id || 1, line_id: "L#{issue.id}")
  end

  def bool_field(name)
    IssueCustomField.create!(name: name, field_format: 'bool', is_for_all: true, tracker_ids: Tracker.ids)
  end

  def with_ticket_settings(values)
    Setting.plugin_redmine_qbo_tickets = RedmineQboTickets::Settings::DEFAULTS.merge(values)
    yield
  end

  # A black PNG the receipt's width, as the dialog sends it
  def png(width: 576, height: 20)
    chunk = lambda do |type, data|
      [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
    end
    rows = ("\x00".b + ("\xFF".b * ((width + 7) / 8))) * height
    LabelJob::PNG_SIGNATURE + chunk.call('IHDR', [width, height, 1, 0, 0, 0, 0].pack('NNCCCCC')) +
      chunk.call('IDAT', Zlib::Deflate.deflate(rows)) + chunk.call('IEND', ''.b)
  end
end
