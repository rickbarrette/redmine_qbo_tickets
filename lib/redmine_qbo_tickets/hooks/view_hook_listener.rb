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
  module Hooks
    # "Print key ticket" and "Print reminder" in an appointment's top-right actions, and "Print intake form" in
    # a customer's (the links add the dialog's script and styles to the page, ticket_hooks/assets)
    class ViewHookListener < Redmine::Hook::ViewListener
      # redmine_qbo_calendar's :view_customer_appointments_show_contextual
      def view_customer_appointments_show_contextual(context = {})
        appointment = context[:appointment]
        return '' if appointment.nil? || appointment.call_out?

        { print_key_tickets: 'ticket_hooks/print_link', print_reminder_tickets: 'ticket_hooks/print_reminder_link' }
          .select { |permission, _| RedmineQboTickets.printing_available?(permission) }
          .map { |_, partial| context[:hook_caller].render(partial: partial, locals: { appointment: appointment }) }
          .join.html_safe
      end

      # redmine_qbo's :view_customers_show_contextual: a vehicle intake form for the customer (with what's
      # ticked on the page, e.g. a vehicle)
      def view_customers_show_contextual(context = {})
        customer = context[:customer]
        return '' if customer.nil? || !RedmineQboTickets.intake_available?

        context[:hook_caller].render(partial: 'ticket_hooks/intake_link', locals: { customer: customer })
      end
    end
  end
end
