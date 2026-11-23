#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQboTickets
  # A vehicle intake form, printed from a customer's page (or a page that links to it, e.g. redmine_qbo_vehicles'
  # vehicle page) when there's no appointment: drawn like a key ticket, with the customer's name big at the top,
  # their details, other plugins' lines (e.g. the vehicle), the work order custom fields to fill in at intake,
  # lines for notes and a QR code. It goes in the key folder like a key ticket.
  #
  # The link's other params (e.g. the vehicle ticked on the customer page, vehicle_id) are kept: they're given
  # to the hooks and sent back with the picture. Hooks (as on key tickets, with appointment nil):
  #   :qbo_tickets_details  context customer:, params:, base_url:, kind: 'intake'; [label, value] lines
  #   :qbo_tickets_qr       the same context; { url:, caption: }. Without one, the QR code opens the customer
  class IntakeForm
    include IntakeFields

    SOURCE_TYPE = 'customer'
    # Params that are the dialog's own, not the link's
    OWN_PARAMS = %w[controller action format customer_id image copies printer_id authenticity_token _].freeze

    attr_reader :customer, :params

    # The form the print dialog's params name: customer_id, and other plugins' params
    def self.from_params(params)
      find(params[:customer_id], extra_params(params))
    end

    # The customer's form, when the current user may see customers
    def self.find(customer_id, params = {})
      return nil unless User.current.allowed_to?(:view_customers, nil, global: true)

      customer = Customer.find_by(id: customer_id)
      customer ? new(customer, params) : nil
    end

    # The request's other plain params, e.g. { 'vehicle_id' => '12' }
    def self.extra_params(params)
      hash = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      hash.each_with_object({}) do |(key, value), extra|
        key = key.to_s
        next if OWN_PARAMS.include?(key) || !key.match?(/\A[a-z][a-z0-9_]{0,40}\z/)
        next unless value.is_a?(String) || value.is_a?(Numeric)

        extra[key] = value.to_s.truncate(100) if value.to_s.present?
      end
    end

    def initialize(customer, params = {})
      @customer = customer
      @params = params.to_h.stringify_keys.freeze
    end

    # Intake has no work order yet: the fields are left blank
    def issue
      nil
    end

    def source_id
      customer.id
    end

    def dialog_params
      params.merge('customer_id' => customer.id)
    end

    # The customer's last name (as on part labels)
    def name
      text = RedmineQboLabels::LabelSource.last_name(customer).presence || customer.name.to_s
      Settings.uppercase? ? text.upcase : text
    end

    # [label, value] lines: the customer, their phone and other plugins' lines (e.g. the vehicle)
    def details
      lines = [[I18n.t(:label_customer, default: 'Customer'), customer.name]]
      phone = Ticket.phone(customer.phone_number.presence || customer.mobile_phone_number)
      lines << [I18n.t(:label_qbo_tickets_phone), phone] if phone.present?
      lines.concat(hook_details)
      lines.map { |label, value| [label.to_s, value.to_s.squish] }.reject { |_, value| value.blank? }
    end

    def qr
      found = RedmineQboTickets.hook_first(:qbo_tickets_qr, hook_context)
      if found && found[:url].present?
        { url: found[:url].to_s, caption: found[:caption].to_s }
      else
        { url: Ticket.base_url + Rails.application.routes.url_helpers.customer_path(customer),
          caption: I18n.t(:text_qbo_tickets_qr_customer) }
      end
    end

    # The print job's title, e.g. "Intake form: SMITH"
    def title
      I18n.t(:label_qbo_tickets_intake_job_title, name: name)
    end

    def as_json(*)
      {
        kind: 'intake', name: name, when: nil, number: I18n.t(:label_qbo_tickets_intake_heading),
        details: details, job: nil, notes: [], fields: fields, note_lines: Settings.note_lines, qr: qr,
        labels: Ticket.labels
      }
    end

    private

    def hook_context
      { appointment: nil, customer: customer, params: params, base_url: Ticket.base_url, kind: 'intake' }
    end

    def hook_details
      RedmineQboTickets.hook_list(:qbo_tickets_details, hook_context)
                       .select { |line| line.is_a?(Array) && line.size == 2 }
    end
  end
end
