package com.scarriffle.calendarr.data.remote

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

private val JSON = "application/json; charset=utf-8".toMediaType()

/** Build a JSON request body from key/value pairs, dropping null values. */
fun jsonBody(vararg pairs: Pair<String, Any?>): RequestBody {
    val obj = JSONObject()
    for ((k, v) in pairs) {
        if (v != null) obj.put(k, v)
    }
    return obj.toString().toRequestBody(JSON)
}

/** Build a JSON request body from a map, dropping null values. */
fun jsonBody(map: Map<String, Any?>): RequestBody {
    val obj = JSONObject()
    for ((k, v) in map) {
        if (v != null) obj.put(k, v)
    }
    return obj.toString().toRequestBody(JSON)
}
