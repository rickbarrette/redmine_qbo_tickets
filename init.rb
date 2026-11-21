Redmine::Plugin.register :redmine_qbo_tickets do

  # About
  name 'Redmine QBO Tickets plugin'
  author 'Rick Barrette'
  description 'Prints key tickets for appointments on a receipt printer: the customer, the appointment, the work order\'s custom fields to fill in at intake, room for notes, and a QR code'
  version '2026.11.0'
  url 'https://github.com/rickbarrette/redmine_qbo_tickets'
  author_url 'https://barrettefabrication.com'
  requires_redmine version_or_higher: '7.0.0'

  # Customers live in redmine_qbo, appointments in redmine_qbo_calendar, and the receipt printer and its print
  # agent in redmine_qbo_labels (plugins load by name, so all three are registered by now)
  {
    redmine_qbo: ['2026.11.0', 'https://github.com/rickbarrette/redmine_qbo'],
    redmine_qbo_calendar: ['2026.11.12', 'https://github.com/rickbarrette/redmine_qbo_calendar'],
    redmine_qbo_labels: ['2026.11.3', 'https://github.com/rickbarrette/redmine_qbo_labels']
  }.each do |plugin, (version, url)|
    begin
      requires_redmine_plugin plugin, version_or_higher: version
    rescue Redmine::PluginNotFound
      raise "Please install the #{plugin} plugin (#{url})"
    end
  end

  settings default: RedmineQboTickets::Settings::DEFAULTS.dup, partial: 'settings/qbo_tickets'

  # The Print key ticket dialog, sending the ticket and following its print job
  permission :print_key_tickets, { key_tickets: [:new, :create, :show] }, global: true
end

RedmineQboTickets.setup
