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
  # What goes on an appointment reminder, a ticket the customer takes home when they book: the shop's logo and
  # details at the top (from the settings), when they're due in big letters, the appointment's details, a
  # message (e.g. how to reschedule), and a QR code that adds the appointment to their phone's calendar (or
  # opens the shop's website).
  #
  # The browser draws it (assets/javascripts/qbo_tickets.js) from #as_json, and sends the picture to the
  # receipt printer, as for key tickets.
  #
  # Other plugins add lines with :qbo_tickets_details, as on key tickets; the context's kind is 'reminder' (and
  # 'key' on key tickets), for lines only the shop should see. Nothing internal is printed: no phone, work
  # order or technician, and the appointment's notes only when the settings say so.
  class Reminder
    # The calendar entry's length; the appointment's own length is in working days, the time the vehicle stays
    EVENT_MINUTES = 30

    attr_reader :appointment

    # The appointment's reminder, when the current user may see the appointment and it's not a call-out
    def self.find(id)
      appointment = CustomerAppointment.visible.find_by(id: id)
      appointment && !appointment.call_out? ? new(appointment) : nil
    end

    def initialize(appointment)
      @appointment = appointment
    end

    def customer
      appointment.customer
    end

    # The shop's name and its details' lines (address, phone, website), centered under the logo
    def shop
      lines = Settings.shop_address_lines
      lines << Settings.shop_phone if Settings.shop_phone.present?
      lines << Settings.shop_website if Settings.shop_website.present?
      { name: Settings.shop_name, lines: lines }
    end

    # When they're due, e.g. { day: 'Monday', date: 'November 23, 2026', time: '8:30 AM' }
    def due
      date = appointment.date
      return { day: '', date: '', time: '' } unless date

      { day: date.strftime('%A'), date: date.strftime('%B %-d, %Y'), time: date.strftime('%-l:%M %p') }
    end

    # [label, value] lines: the customer, other plugins' lines (e.g. the vehicle), the job, the estimate and,
    # when the appointment takes more than a day, how long
    def details
      lines = []
      lines << [I18n.t(:label_customer, default: 'Customer'), customer.name] if customer
      lines.concat(hook_details)
      lines << [I18n.t(:label_qbo_tickets_job), appointment.subject]
      lines << [I18n.t(:label_estimate, default: 'Estimate'), "E#{appointment.estimate.doc_number}"] if appointment.estimate&.doc_number.present?
      days = appointment.duration.to_i
      lines << [I18n.t(:label_qbo_tickets_reminder_length), I18n.t(:label_qbo_tickets_reminder_days, count: days)] if days > 1
      lines.map { |label, value| [label.to_s, value.to_s.squish] }.reject { |_, value| value.blank? }
    end

    # The appointment's notes, formatted, when the settings print them
    def notes
      return [] unless Settings.reminder_notes?

      text = appointment.description.to_s.gsub(/\r\n?/, "\n").strip
      RichText.blocks(text.gsub(/(?<![\w#])##(\d+)\b/, 'W\\1').truncate(Ticket::NOTES_LENGTH))
    end

    # { text:, caption: } for the QR code, or nil
    def qr
      case Settings.reminder_qr
      when 'calendar'
        text = calendar_entry
        text ? { text: text, caption: I18n.t(:text_qbo_tickets_qr_calendar) } : nil
      when 'website'
        url = website_url
        url ? { text: url, caption: I18n.t(:text_qbo_tickets_qr_website) } : nil
      end
    end

    # The appointment as a calendar entry (iCalendar's VEVENT, which phones' cameras offer to add to the
    # calendar), or nil without a date
    def calendar_entry
      date = appointment.date
      return nil unless date

      shop_name = Settings.shop_name
      summary = [shop_name.presence, appointment.subject.to_s.squish.presence].compact.join(': ')
      summary = I18n.t(:label_qbo_tickets_reminder_event) if summary.blank?
      format = ->(time) { time.utc.strftime('%Y%m%dT%H%M%SZ') }
      lines = ['BEGIN:VEVENT', "SUMMARY:#{ical_escape(summary)}", "DTSTART:#{format.call(date)}",
               "DTEND:#{format.call(date + EVENT_MINUTES.minutes)}"]
      location = Settings.shop_address_lines.join(', ')
      lines << "LOCATION:#{ical_escape(location)}" if location.present?
      lines << "DESCRIPTION:#{ical_escape(Settings.shop_phone)}" if Settings.shop_phone.present?
      (lines << 'END:VEVENT').join("\n")
    end

    # The shop's website as a link (https:// added when it has no scheme), or nil
    def website_url
      site = Settings.shop_website
      return nil if site.blank?

      site.match?(%r{\Ahttps?://}i) ? site : "https://#{site}"
    end

    # The print job's title, e.g. "Reminder: Jane Q Smith (appointment #12)"
    def title
      I18n.t(:label_qbo_tickets_reminder_job_title, name: customer&.name || appointment.subject, id: appointment.id)
    end

    def as_json(*)
      {
        kind: 'reminder', logo: Settings.logo, shop: shop, due: due, details: details, notes: notes,
        message: Settings.reminder_message, qr: qr,
        labels: { heading: I18n.t(:label_qbo_tickets_reminder_heading), notes: I18n.t(:label_qbo_tickets_appointment_notes) }
      }
    end

    private

    def hook_details
      RedmineQboTickets.hook_list(:qbo_tickets_details, appointment: appointment, base_url: Ticket.base_url,
                                                        kind: 'reminder')
                       .select { |line| line.is_a?(Array) && line.size == 2 }
    end

    def ical_escape(text)
      text.to_s.gsub('\\', '\\\\\\\\').gsub(/\r?\n/, '\\n').gsub(',', '\\,').gsub(';', '\;')
    end
  end
end
