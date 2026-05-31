package com.scarriffle.calendarr.data.remote

import okhttp3.ResponseBody
import org.json.JSONObject
import retrofit2.Response

/** Generic server error carrying the `detail` message when available. */
open class ApiException(message: String) : Exception(message)

/** Credentials rejected (HTTP 401, not a 2FA prompt). */
class UnauthorizedException : ApiException("Benutzername oder Passwort falsch")

/** Server requires a TOTP code to finish login (HTTP 401, detail "2fa_required"). */
class TwoFactorRequiredException : ApiException("2FA-Code erforderlich")

/** Extract the `detail` field from an error response body, with a fallback. */
fun errorDetail(errorBody: ResponseBody?, status: Int): String {
    val raw = runCatching { errorBody?.string() }.getOrNull()
    if (!raw.isNullOrBlank()) {
        runCatching {
            val detail = JSONObject(raw).optString("detail")
            if (detail.isNotBlank()) return detail
        }
    }
    return "Fehler $status"
}

/** Throw an [ApiException] if the response is unsuccessful. */
fun Response<*>.ensureSuccess() {
    if (!isSuccessful) {
        if (code() == 401) throw UnauthorizedException()
        throw ApiException(errorDetail(errorBody(), code()))
    }
}
