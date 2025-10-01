# frozen_string_literal: true

Rails.application.routes.draw do
  mount RedmineExtendedApi.proxy_app => RedmineExtendedApi::API_PREFIX
end
