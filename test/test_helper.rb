require File.expand_path('../../../test/test_helper', __dir__)

# SPR-546: in the tenant image this plugin always runs next to redmine_openid_connect, which
# refuses Redmine's own credentials — Basic included — and signs users in by Keycloak Bearer
# token only. The suites here keep naming their user through core's `credentials(login,
# password)`; when that plugin is loaded, the header becomes a Bearer token resolved to the
# user Basic would have found, so a wrong password still ends in 401. Without the plugin
# (e.g. a bare Redmine checkout) core's Basic header is used unchanged.
module ExtendedApiBearerCredentials
  def credentials(user, password = nil)
    return super unless defined?(RedmineOpenidConnect::ApplicationControllerPatch)

    token = "test-#{SecureRandom.hex(8)}"
    found = User.try_to_login(user, password || user) || User.find_by_api_key(user)
    ApplicationController.any_instance.stubs(:find_user_by_oidc_token).with(token).returns(found)
    { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
  end
end

Redmine::IntegrationTest.prepend(ExtendedApiBearerCredentials)
