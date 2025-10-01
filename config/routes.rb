# frozen_string_literal: true

Rails.application.routes.draw do
  constraints format: /(json|xml)/, id: /\d+/ do
    get 'custom_fields/:id(.:format)', to: 'custom_fields#show', as: nil
    get 'enumerations/:id(.:format)', to: 'enumerations#show', as: nil
    get 'issue_statuses/:id(.:format)', to: 'issue_statuses#show', as: nil
    get 'trackers/:id(.:format)', to: 'trackers#show', as: nil
  end

  mount RedmineExtendedApi.proxy_app => RedmineExtendedApi::API_PREFIX
end
