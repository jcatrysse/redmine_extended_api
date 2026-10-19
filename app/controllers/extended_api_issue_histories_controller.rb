# frozen_string_literal: true

# POST /extended_api/issues/:id/history.json (decision 41 of the Jira migration, 2026-10-19):
# writes imported history journals (status, assignee and priority changes) with their own user
# and time, and attaches uploaded files, without saving the issue. Journals and details are
# written with insert_all, so no callback runs: no watcher (Journal#add_watcher), no mail, no
# webhook, no job of another plugin; updated_on, closed_on and status_id of the issue stay as
# they are. Admin only, /extended_api only.
class ExtendedApiIssueHistoriesController < ApplicationController
  include RedmineExtendedApi::Patches::ApiHelpers

  # property attr only; the key decides which records a value must name
  HISTORY_KEYS = {
    'status_id' => -> (id) { IssueStatus.where(id: id).exists? },
    'assigned_to_id' => -> (id) { Principal.where(id: id, type: %w[User Group]).exists? },
    'priority_id' => -> (id) { IssuePriority.where(id: id).exists? }
  }.freeze
  # an assignee can be removed; a status or priority is always set
  HISTORY_KEYS_ALLOWING_NIL = %w[assigned_to_id].freeze

  # an upload attached meanwhile (the same token twice, or another request): rolls back
  class UploadTaken < StandardError; end

  accept_api_auth :create

  before_action :require_extended_api_history_request
  before_action :find_extended_api_history_issue

  def create
    journals = Array.wrap(history_param(:journals))
    attachments = Array.wrap(history_param(:attachments))

    errors = extended_api_history_errors(journals) + extended_api_history_attachment_errors(attachments)
    return render_api_error_message(errors.uniq) if errors.any?

    journal_ids = attachment_ids = nil
    begin
      Journal.transaction do
        journal_ids = insert_extended_api_history_journals(journals)
        attachment_ids = attach_extended_api_history_files(attachments)
      end
    rescue UploadTaken
      return render_api_error_message([extended_api_history_invalid(:token)])
    end

    mark_extended_api_response(fallback: false)
    render json: {journal_ids: journal_ids, attachment_ids: attachment_ids}, status: :created
  end

  private

  # 404 on the core path (like the plugin's show routes), 401 without a user, 403 for a
  # non-admin before the issue is looked up.
  def require_extended_api_history_request
    return render_404 unless extended_api_request?
    return require_login unless User.current.logged?
    return if User.current.admin?

    render_api_error_message(I18n.t(:notice_not_authorized), status: 403)
  end

  # An archived project (or one being deleted) is read-only for everyone in core, admins
  # included; a closed project is not refused: an import may close its projects first.
  def find_extended_api_history_issue
    @issue = Issue.find(params[:id])
    project = @issue.project
    return if project.active? || project.closed?

    render_api_error_message(I18n.t(:notice_not_authorized), status: 403)
  rescue ActiveRecord::RecordNotFound
    render_api_not_found
  end

  # The JSON body as given; the values are checked one by one below and never mass assigned.
  def history_param(key)
    value = params[key]
    return value.map { |v| history_hash(v) } if value.is_a?(Array)

    value.nil? ? nil : [history_hash(value)]
  end

  def history_hash(value)
    if value.respond_to?(:to_unsafe_h)
      value.to_unsafe_h
    elsif value.is_a?(Hash)
      value.with_indifferent_access
    else
      value
    end
  end

  def extended_api_history_invalid(key)
    label = I18n.t(:"field_#{key.to_s.delete_suffix('_id')}", default: key.to_s.humanize)
    "#{label} #{I18n.t('activerecord.errors.messages.invalid', default: 'is invalid')}"
  end

  def extended_api_history_errors(journals)
    return [extended_api_history_invalid(:history)] if journals.empty?

    journals.flat_map do |journal|
      next [extended_api_history_invalid(:history)] unless journal.is_a?(Hash)

      errors = []
      errors << extended_api_history_invalid(:user_id) unless extended_api_user_exists?(journal[:user_id])
      errors << extended_api_history_invalid(:created_on) unless parse_extended_api_time(journal[:created_on].presence)
      errors << extended_api_history_invalid(:notes) if journal[:notes].present? || extended_api_history_private?(journal)

      details = journal[:details]
      if !details.is_a?(Array) || details.empty?
        errors << extended_api_history_invalid(:details)
      else
        details.each { |detail| errors.concat(extended_api_history_detail_errors(detail)) }
      end
      errors
    end
  end

  # private_notes is refused unless it says "not private"
  def extended_api_history_private?(journal)
    journal.key?(:private_notes) && !['', 'false', '0'].include?(journal[:private_notes].to_s)
  end

  def extended_api_history_detail_errors(detail)
    detail = history_hash(detail)
    return [extended_api_history_invalid(:details)] unless detail.is_a?(Hash)
    return [extended_api_history_invalid(:property)] unless detail[:property].to_s == 'attr'

    key = detail[:prop_key].to_s
    exists = HISTORY_KEYS[key]
    return [extended_api_history_invalid(:prop_key)] unless exists

    [detail[:old_value], detail[:value]].each_with_index.filter_map do |value, index|
      next if value.nil? && (index.zero? || HISTORY_KEYS_ALLOWING_NIL.include?(key))
      next if value.to_s.match?(/\A\d+\z/) && exists.call(value.to_i)

      extended_api_history_invalid(key)
    end
  end

  def extended_api_history_attachment_errors(attachments)
    attachments.flat_map do |attachment|
      next [extended_api_history_invalid(:attachments)] unless attachment.is_a?(Hash)

      errors = []
      errors << extended_api_history_invalid(:token) unless Attachment.find_by_token(attachment[:token])
      errors << extended_api_history_invalid(:author_id) unless extended_api_user_exists?(attachment[:author_id])
      errors << extended_api_history_invalid(:created_on) unless parse_extended_api_time(attachment[:created_on].presence)
      # written with update_all, past the model's validations: core's limit of 255 for filename
      # and description, and the string column of content_type (255 on MySQL)
      %i[filename content_type description].each do |key|
        errors << extended_api_history_invalid(key) if attachment[key].to_s.length > 255
      end
      errors
    end
  end

  # One row per journal: notes '', not private, updated_on = created_on, updated_by_id empty
  # (not edited). PostgreSQL returns the ids in insert order; without RETURNING each journal is
  # inserted alone and its id read back on the same connection (MySQL/MariaDB LAST_INSERT_ID(),
  # not shared with concurrent requests).
  def insert_extended_api_history_journals(journals)
    rows = journals.map do |journal|
      time = parse_extended_api_time(journal[:created_on])
      {journalized_id: @issue.id, journalized_type: 'Issue', user_id: journal[:user_id].to_i,
       notes: '', private_notes: false, created_on: time, updated_on: time, updated_by_id: nil}
    end

    ids =
      if Journal.connection.supports_insert_returning?
        Journal.insert_all(rows, returning: %w[id]).rows.map { |row| row.first.to_i }
      else
        rows.map do |row|
          Journal.insert_all([row])
          extended_api_last_insert_id(row)
        end
      end

    details = journals.zip(ids).flat_map do |journal, journal_id|
      journal[:details].map do |detail|
        detail = history_hash(detail)
        {journal_id: journal_id, property: 'attr', prop_key: detail[:prop_key].to_s,
         old_value: detail[:old_value]&.to_s, value: detail[:value]&.to_s}
      end
    end
    JournalDetail.insert_all(details)

    ids
  end

  def extended_api_last_insert_id(row)
    connection = Journal.connection
    if connection.adapter_name.to_s.match?(/mysql|maria/i)
      connection.select_value('SELECT LAST_INSERT_ID()').to_i
    else
      Journal.where(row.slice(:journalized_id, :journalized_type, :user_id, :created_on)).maximum(:id)
    end
  end

  # The upload becomes a file of the issue with the given author and time; no journal, the
  # issue is not saved. update_all: no callback of the attachment or of the issue runs.
  def attach_extended_api_history_files(attachments)
    attachments.map do |given|
      attachment = Attachment.find_by_token(given[:token])
      raise UploadTaken unless attachment

      cols = {container_id: @issue.id, container_type: 'Issue',
              author_id: given[:author_id].to_i, created_on: parse_extended_api_time(given[:created_on])}
      if given[:filename].present?
        attachment.filename = given[:filename].to_s # core's sanitizing setter
        cols[:filename] = attachment.filename
      end
      cols[:content_type] = given[:content_type].to_s if given[:content_type].present?
      cols[:description] = given[:description].to_s if given.key?(:description)
      # only while it is still unattached
      raise UploadTaken if Attachment.where(id: attachment.id, container_id: nil).update_all(cols).zero?

      attachment.id
    end
  end
end
