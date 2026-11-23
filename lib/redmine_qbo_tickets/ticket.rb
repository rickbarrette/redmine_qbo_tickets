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
  # What goes on an appointment's key ticket. The ticket goes in the key folder at drop-off, before the vehicle's
  # intake, so it names the customer in big letters at the top (readable above the folder's edge), gives the
  # appointment's details, has the work order's custom fields to fill in at intake (or their values, when the
  # appointment's work order already has them), lines for notes, and a QR code.
  #
  # The browser draws it (assets/javascripts/qbo_tickets.js) from #as_json, and sends the picture to the receipt
  # printer.
  #
  # Other plugins add to it with hooks (context: appointment, base_url, e.g. https://redmine.example.com):
  #   :qbo_tickets_details  an array of [label, value] lines under the customer, e.g. [['Vehicle', '2019 Jeep']]
  #                         (the context's kind is 'key'; Reminder calls it with 'reminder')
  #   :qbo_tickets_qr       { url:, caption: } for the QR code (the first listener's); without one, the QR code
  #                         opens the appointment
  class Ticket
    include IntakeFields

    NOTES_LENGTH = 1000

    attr_reader :appointment

    # The appointment's ticket, when the current user may see the appointment and it's not a call-out
    def self.find(id)
      appointment = CustomerAppointment.visible.find_by(id: id)
      appointment && !appointment.call_out? ? new(appointment) : nil
    end

    # The ticket the print dialog's params name (appointment_id)
    def self.from_params(params)
      find(params[:appointment_id])
    end

    # The print job's source (redmine_qbo_labels' LabelSource), and what the dialog sends back with the picture
    SOURCE_TYPE = 'appointment'

    def source_id
      appointment.id
    end

    def dialog_params
      { appointment_id: appointment.id }
    end

    def initialize(appointment)
      @appointment = appointment
    end

    def customer
      appointment.customer
    end

    # The appointment's newest work order the user may see (made from its estimate), whose custom field
    # values are printed
    def issue
      return @issue if defined?(@issue)

      @issue = appointment.created_issues.visible.order(id: :desc).first
    end

    # The customer's last name (as on part labels), or the appointment's subject without a customer
    def name
      text = customer ? RedmineQboLabels::LabelSource.last_name(customer).presence || customer.name : nil
      text = text.presence || appointment.subject.to_s
      Settings.uppercase? ? text.upcase : text
    end

    # When the customer's due, as the appointment's page shows it, e.g. "Sat 11/22/2026 · 8:30 AM"
    def when_text
      date = appointment.date
      date ? "#{date.strftime('%a %-m/%-d/%Y')} · #{date.strftime('%-l:%M %p')}" : ''
    end

    def number
      I18n.t(:label_qbo_tickets_appointment_number, id: appointment.id)
    end

    # [label, value] lines: the customer, their phone, other plugins' lines (e.g. the vehicle), the estimate,
    # the work order and the technician
    def details
      lines = []
      if customer
        lines << [I18n.t(:label_customer, default: 'Customer'), customer.name]
        phone = self.class.phone(customer.phone_number.presence || customer.mobile_phone_number)
        lines << [I18n.t(:label_qbo_tickets_phone), phone] if phone.present?
      end
      lines.concat(hook_details)
      lines << [I18n.t(:label_estimate, default: 'Estimate'), "E#{appointment.estimate.doc_number}"] if appointment.estimate&.doc_number.present?
      lines << [I18n.t(:label_qbo_tickets_work_order), "W#{issue.id}"] if issue
      lines << [I18n.t(:label_qbo_tickets_technician), appointment.user.name] if appointment.user
      lines.map { |label, value| [label.to_s, value.to_s.squish] }.reject { |_, value| value.blank? }
    end

    # The job (the appointment's subject)
    def job
      appointment.subject.to_s.squish
    end

    # The appointment's notes (its description) as written, with issue references (##1234) as work order
    # numbers (W1234)
    def notes_text
      text = appointment.description.to_s.gsub(/\r\n?/, "\n").strip
      text.gsub(/(?<![\w#])##(\d+)\b/, 'W\\1').truncate(NOTES_LENGTH)
    end

    # The notes formatted as Redmine formats them (Markdown or Textile), as blocks the ticket draws (RichText)
    def notes
      RichText.blocks(notes_text)
    end

    def qr
      found = RedmineQboTickets.hook_first(:qbo_tickets_qr, appointment: appointment, base_url: self.class.base_url)
      if found && found[:url].present?
        { url: found[:url].to_s, caption: found[:caption].to_s }
      else
        { url: self.class.base_url + url_helpers.customer_appointment_path(appointment),
          caption: I18n.t(:text_qbo_tickets_qr_appointment) }
      end
    end

    # The print job's title, e.g. "Key ticket: SMITH (appointment #12)"
    def title
      I18n.t(:label_qbo_tickets_job_title, name: name, id: appointment.id)
    end

    def as_json(*)
      {
        name: name, when: when_text, number: number, details: details, job: job, notes: notes,
        fields: fields, note_lines: Settings.note_lines, qr: qr,
        labels: self.class.labels
      }
    end

    # The headings and words a ticket drawn like a key ticket prints
    def self.labels
      {
        yes: I18n.t(:general_text_Yes), no: I18n.t(:general_text_No), notes: I18n.t(:label_qbo_tickets_notes),
        job: I18n.t(:label_qbo_tickets_job), intake: I18n.t(:label_qbo_tickets_intake),
        appointment_notes: I18n.t(:label_qbo_tickets_appointment_notes),
        intake_notes: I18n.t(:label_qbo_tickets_intake_notes),
        # %{time} is filled in by the browser when the ticket is printed
        printed: I18n.t(:label_qbo_tickets_printed, time: '%{time}')
      }
    end

    # Redmine's address (Administration » Settings: protocol and host name), for links in QR codes
    def self.base_url
      "#{Setting.protocol}://#{Setting.host_name}".chomp('/')
    end

    # (401) 555-0100 for 10 digits (or 11 starting with 1), else as it is
    def self.phone(number)
      digits = number.to_s.gsub(/\D/, '')
      digits = digits[1..] if digits.length == 11 && digits.start_with?('1')
      digits.length == 10 ? "(#{digits[0, 3]}) #{digits[3, 3]}-#{digits[6, 4]}" : number.to_s
    end

    private

    def url_helpers
      Rails.application.routes.url_helpers
    end

    def hook_details
      RedmineQboTickets.hook_list(:qbo_tickets_details, appointment: appointment, base_url: self.class.base_url,
                                                        kind: 'key')
                       .select { |line| line.is_a?(Array) && line.size == 2 }
    end
  end
end
