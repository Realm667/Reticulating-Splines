class_name ReleaseUpdateCheck
extends RefCounted
## Rules for the optional check for a newer published Reticulating Splines release on GitHub.
## The check only reports a release. The player downloads and installs it.

enum Status {
	UPDATE_AVAILABLE,
	UP_TO_DATE,
	FAILED,
}

const REPOSITORY := "Realm667/Reticulating-Splines"
const LATEST_RELEASE_API := "https://api.github.com/repos/" + REPOSITORY + "/releases?per_page=100"
const LATEST_RELEASE_PAGE := "https://github.com/" + REPOSITORY + "/releases"
const RELEASE_PAGE_PREFIX := "https://github.com/" + REPOSITORY + "/releases/tag/"
# send only the headers that the GitHub API requires. the explicit user agent
# replaces the engine default, which includes the engine version and system
const REQUEST_HEADERS := [
	"Accept: application/vnd.github+json",
	"X-GitHub-Api-Version: 2022-11-28",
	"User-Agent: ReticulatingSplines",
]
const CHECK_INTERVAL_SECONDS := 24 * 60 * 60
const TIMEOUT_SECONDS := 20.0
const BODY_SIZE_LIMIT := 1024 * 1024


static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


# Keep the native strict base parser; the fork additionally uses -rs.N[-dev.N].
# Stable bases sort after their RS previews, and an RS release after its dev builds.
static func parse_version(value: String) -> Array[int]:
	var result: Array[int] = []
	var parts := value.strip_edges().split("-rs.")
	result.assign(Array(NativePlatform.parse_version(parts[0])))
	if result.is_empty() or parts.size() == 1:
		return result
	if parts.size() != 2:
		return []
	var suffix := RegEx.create_from_string("^([1-9][0-9]{0,4})(?:-dev\\.([1-9][0-9]{0,4}))?$").search(parts[1])
	if suffix == null:
		return []
	var revision := int(suffix.get_string(1))
	var development := int(suffix.get_string(2)) if not suffix.get_string(2).is_empty() else 65536
	if revision > 65535 or (development > 65535 and not suffix.get_string(2).is_empty()):
		return []
	result.append(revision)
	result.append(development)

	return result


static func normalized_version(value: String) -> String:
	if parse_version(value).is_empty():
		return ""
	return value.strip_edges().trim_prefix("v")


static func is_newer(candidate: String, current: String) -> bool:
	var left := parse_version(candidate)
	var right := parse_version(current)
	if left.is_empty() or right.is_empty():
		return false
	for index in range(5):
		var a := left[index] if index < left.size() else 65536
		var b := right[index] if index < right.size() else 65536
		if a != b:
			return a > b
	return false


# a clock that moved back must not stop the daily check
static func is_due(last_check: int, now: int) -> bool:
	return NativePlatform.is_due(last_check, now)


static func failed(message: String) -> Outcome:
	var outcome := Outcome.new()
	outcome.message = message

	return outcome


static func read_response(
	result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, current: String, now: int
) -> Outcome:
	var transport := "other"

	match result:
		HTTPRequest.RESULT_SUCCESS:
			transport = "success"
		HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CANT_CONNECT, \
				HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_NO_RESPONSE:
			transport = "connect"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			transport = "tls"
		HTTPRequest.RESULT_TIMEOUT:
			transport = "timeout"

	# Existing translated transport/rate-limit/HTTP errors remain owned by native.
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) != OK or not json.data is Array:
			return failed("GitHub returned release information that Reticulating Splines cannot read.")
		return select_release(json.data, current)
	var fields := NativePlatform.read_response(transport, result, response_code, headers, body, current, now)
	var outcome := Outcome.new()
	outcome.status = fields.status as Status
	outcome.version = fields.version
	outcome.url = fields.url
	outcome.message = fields.message

	return outcome


static func select_release(releases: Array, current: String) -> Outcome:
	if parse_version(current).is_empty():
		return failed("GitHub returned release information that Reticulating Splines cannot read.")
	var newest := Outcome.new()
	for entry in releases:
		if not entry is Dictionary or entry.get("draft") != false:
			continue
		var published: Variant = entry.get("published_at")
		var tag: Variant = entry.get("tag_name")
		if not published is String or published.is_empty() or not tag is String:
			continue
		var version := normalized_version(tag)
		if version.is_empty() or (not newest.version.is_empty() and not is_newer(version, newest.version)):
			continue
		newest.version = version
		# Never open a foreign URL or a different tag supplied in release metadata.
		var expected: String = RELEASE_PAGE_PREFIX + tag
		newest.url = expected if entry.get("html_url") == expected else LATEST_RELEASE_PAGE
	if newest.version.is_empty():
		return failed("GitHub has no published Reticulating Splines release.")
	newest.status = Status.UPDATE_AVAILABLE if is_newer(newest.version, current) else Status.UP_TO_DATE
	return newest


# seconds until GitHub accepts requests again, or -1 when the response is not a rate limit
static func retry_seconds(headers: PackedStringArray, now: int) -> int:
	return NativePlatform.retry_seconds(headers, now)


static func wait_text(seconds: int) -> String:
	return NativePlatform.wait_text(seconds)


# summary of the last check in local time, for example "Last checked 2026-09-25 14:05."
static func status_text(checked_at: int, error: String, bias_minutes := int(Time.get_time_zone_from_system().bias)) -> String:
	if checked_at <= 0:
		return ""
	var stamp := Time.get_datetime_string_from_unix_time(checked_at + bias_minutes * 60).replace("T", " ").substr(0, 16)
	if error.is_empty():
		return TranslationServer.translate("Last checked %s.") % stamp
	return TranslationServer.translate("Last check failed %s. %s") % [stamp, AppLocalization.message(error)]


static func header_value(headers: PackedStringArray, header_name: String) -> String:
	return NativePlatform.header_value(headers, header_name)


class Outcome extends RefCounted:
	var status := Status.FAILED
	var version := ""
	var url := LATEST_RELEASE_PAGE
	var message := ""
