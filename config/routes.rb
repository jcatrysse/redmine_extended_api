# frozen_string_literal: true

Rails.application.routes.draw do
  constraints format: /(json|xml)/, id: /\d+/ do
    get 'custom_fields/:id(.:format)', to: 'custom_fields#show', as: nil
    get 'enumerations/:id(.:format)', to: 'enumerations#show', as: nil
    get 'issue_statuses/:id(.:format)', to: 'issue_statuses#show', as: nil
    get 'trackers/:id(.:format)', to: 'trackers#show', as: nil
  end

  # imported history journals (decision 41 of the Jira migration); answers only under /extended_api
  post 'issues/:id/history(.:format)', to: 'extended_api_issue_histories#create', as: nil,
       constraints: {format: 'json', id: /\d+/}

  mount RedmineExtendedApi.proxy_app => RedmineExtendedApi::API_PREFIX
end
