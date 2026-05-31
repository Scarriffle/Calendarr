package com.scarriffle.calendarr.data.remote

import com.scarriffle.calendarr.domain.model.AppSettings
import com.scarriffle.calendarr.domain.model.CalDAVAccount
import com.scarriffle.calendarr.domain.model.GoogleAccount
import com.scarriffle.calendarr.domain.model.HomeAssistantAccount
import com.scarriffle.calendarr.domain.model.ICalSubscription
import com.scarriffle.calendarr.domain.model.LocalCalendar
import com.scarriffle.calendarr.domain.model.UserProfile
import okhttp3.RequestBody
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.HTTP
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * Retrofit definition of the Calendarr server HTTP API.
 *
 * Endpoints whose responses contain mixed-type fields (event `id` /
 * `calendar_id` arrive as either String or Int) return a raw [ResponseBody]
 * and are parsed manually with org.json, mirroring the iOS client.
 */
interface CalendarrApi {

    // ---- Auth ----

    @GET("api/auth/setup-required")
    suspend fun setupRequired(): Response<ResponseBody>

    @POST("api/auth/login")
    suspend fun login(@Body body: RequestBody): Response<ResponseBody>

    @GET("api/auth/me")
    suspend fun getProfile(): UserProfile

    // ---- Settings ----

    @GET("api/settings/")
    suspend fun getSettings(): AppSettings

    @PUT("api/settings/")
    suspend fun updateSettings(@Body body: RequestBody): Response<ResponseBody>

    // ---- Profile ----

    @PATCH("api/profile/")
    suspend fun updateEmail(@Body body: RequestBody): Response<ResponseBody>

    @POST("api/profile/password")
    suspend fun changePassword(@Body body: RequestBody): Response<ResponseBody>

    @POST("api/profile/2fa/setup")
    suspend fun setup2fa(): Response<ResponseBody>

    @POST("api/profile/2fa/enable")
    suspend fun enable2fa(@Body body: RequestBody): Response<ResponseBody>

    @POST("api/profile/2fa/disable")
    suspend fun disable2fa(@Body body: RequestBody): Response<ResponseBody>

    // ---- CalDAV ----

    @GET("api/caldav/accounts")
    suspend fun getCalDAVAccounts(): List<CalDAVAccount>

    @POST("api/caldav/accounts")
    suspend fun addCalDAVAccount(@Body body: RequestBody): CalDAVAccount

    @DELETE("api/caldav/accounts/{id}")
    suspend fun deleteCalDAVAccount(@Path("id") id: Int): Response<ResponseBody>

    @POST("api/caldav/accounts/{id}/sync")
    suspend fun syncCalDAVAccount(@Path("id") id: Int): Response<ResponseBody>

    @PUT("api/caldav/calendars/{id}")
    suspend fun updateCalDAVCalendar(@Path("id") id: Int, @Body body: RequestBody): Response<ResponseBody>

    // ---- Local ----

    @GET("api/local/calendars")
    suspend fun getLocalCalendars(): List<LocalCalendar>

    @POST("api/local/calendars")
    suspend fun addLocalCalendar(@Body body: RequestBody): LocalCalendar

    @DELETE("api/local/calendars/{id}")
    suspend fun deleteLocalCalendar(@Path("id") id: Int): Response<ResponseBody>

    // ---- iCal subscriptions ----

    @GET("api/ical/subscriptions")
    suspend fun getICalSubscriptions(): List<ICalSubscription>

    @POST("api/ical/subscriptions")
    suspend fun addICalSubscription(@Body body: RequestBody): ICalSubscription

    @DELETE("api/ical/subscriptions/{id}")
    suspend fun deleteICalSubscription(@Path("id") id: Int): Response<ResponseBody>

    @POST("api/ical/subscriptions/{id}/refresh")
    suspend fun refreshICalSubscription(@Path("id") id: Int): Response<ResponseBody>

    // ---- Google ----

    @GET("api/google/accounts")
    suspend fun getGoogleAccounts(): List<GoogleAccount>

    @DELETE("api/google/accounts/{id}")
    suspend fun deleteGoogleAccount(@Path("id") id: Int): Response<ResponseBody>

    @PUT("api/google/calendars/{id}")
    suspend fun updateGoogleCalendar(@Path("id") id: Int, @Body body: RequestBody): Response<ResponseBody>

    // ---- Home Assistant ----

    @GET("api/homeassistant/accounts")
    suspend fun getHomeAssistantAccounts(): List<HomeAssistantAccount>

    @POST("api/homeassistant/accounts")
    suspend fun addHomeAssistantAccount(@Body body: RequestBody): HomeAssistantAccount

    @DELETE("api/homeassistant/accounts/{id}")
    suspend fun deleteHomeAssistantAccount(@Path("id") id: Int): Response<ResponseBody>

    @PUT("api/homeassistant/calendars/{id}")
    suspend fun updateHACalendar(@Path("id") id: Int, @Body body: RequestBody): Response<ResponseBody>

    // ---- Events ----

    @GET("api/caldav/events")
    suspend fun fetchEvents(
        @Query("start") start: String,
        @Query("end") end: String,
    ): Response<ResponseBody>

    @POST("api/local/events")
    suspend fun createLocalEvent(@Body body: RequestBody): Response<ResponseBody>

    @PUT("api/local/events/{uid}")
    suspend fun updateLocalEvent(@Path("uid") uid: String, @Body body: RequestBody): Response<ResponseBody>

    @DELETE("api/local/events/{uid}")
    suspend fun deleteLocalEvent(@Path("uid") uid: String): Response<ResponseBody>

    @POST("api/caldav/events")
    suspend fun createCalDAVEvent(@Body body: RequestBody): Response<ResponseBody>

    @PUT("api/caldav/events/{uid}")
    suspend fun updateCalDAVEvent(
        @Path("uid") uid: String,
        @Query("event_url") eventUrl: String,
        @Query("calendar_id") calendarId: Int?,
        @Body body: RequestBody,
    ): Response<ResponseBody>

    @HTTP(method = "DELETE", path = "api/caldav/events/{uid}", hasBody = false)
    suspend fun deleteCalDAVEvent(
        @Path("uid") uid: String,
        @Query("event_url") eventUrl: String,
        @Query("calendar_id") calendarId: Int?,
    ): Response<ResponseBody>

    @POST("api/google/events")
    suspend fun createGoogleEvent(@Body body: RequestBody): Response<ResponseBody>

    @POST("api/homeassistant/events")
    suspend fun createHAEvent(@Body body: RequestBody): Response<ResponseBody>

    @DELETE("api/homeassistant/events/{calendarId}/{uid}")
    suspend fun deleteHAEvent(
        @Path("calendarId") calendarId: Int,
        @Path("uid") uid: String,
    ): Response<ResponseBody>
}
