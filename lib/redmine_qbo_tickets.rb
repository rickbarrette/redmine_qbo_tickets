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

  def self.setup
    # Hooks
    RedmineQboTickets::Hooks::ViewHookListener

    Rails.configuration.to_prepare do
      ApplicationController.prepend_view_path(File.expand_path('../app/views', __dir__))
    end
  end

  PERMISSIONS = %i[print_key_tickets print_reminder_tickets].freeze

  # Whether the current user may print key tickets (or reminders, or either, without a permission) and
  # there's a receipt printer to print on
  def self.printing_available?(permission = nil)
    allowed = Array(permission || PERMISSIONS).any? { |p| User.current.allowed_to?(p, nil, global: true) }
    allowed && LabelPrinter.active.receipts.exists?
  end

  # Whether the current user may print intake forms: Print key tickets, viewing customers, and a receipt printer.
  # Other plugins check it before rendering ticket_hooks/intake_link (e.g. redmine_qbo_vehicles' vehicle page).
  def self.intake_available?
    printing_available?(:print_key_tickets) && User.current.allowed_to?(:view_customers, nil, global: true)
  end

  # The listeners' answers to a hook, flattened, without blanks
  def self.hook_list(hook, context = {})
    Redmine::Hook.call_hook(hook, context).flatten(1).compact_blank
  end

  # The first listener's hash for a hook, or nil
  def self.hook_first(hook, context = {})
    Redmine::Hook.call_hook(hook, context).find { |result| result.is_a?(Hash) && result.present? }
  end
end
