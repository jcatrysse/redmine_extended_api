# Changelog

## 0.0.1

* Initial release exposing default Redmine APIs.
* Added `/extended_api` proxy that mirrors the Redmine REST API while keeping the core endpoints untouched.
* Documented every mirrored Redmine 6.1 endpoint with usage examples in the README.

## 0.0.2

* Enabled POST/PUT/PATCH/DELETE for issue statuses, trackers, enumerations, custom fields and roles.
* Added API serializers that expose all administrative options.
* Documented write operations in the README with cURL examples for JSON clients.
* Added an extended_api metadata block to each extended API template so responses explicitly state whether they originated from the extended feature set or a proxied native endpoint.

## 0.0.3

* Resolved handling of enumerations values in the enumeration custom field.

## 0.0.4

* Added admin-only issue override support (author_id, created_on, updated_on, and closed_on) when routed through the extended API.
* Added admin-only journal override support (user, updated_on and updated_by_id) when routed through the extended API.
* Added admin-only attachment override support (author_id and created_on) when routed through the extended API.
* Documented the new overrides in the README.
