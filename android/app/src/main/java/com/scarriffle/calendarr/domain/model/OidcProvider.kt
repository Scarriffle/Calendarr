package com.scarriffle.calendarr.domain.model

/**
 * One identity provider configured on the Calendarr server, as returned by
 * `GET /api/auth/oidc/providers`.
 */
data class OidcProvider(
    val key: String,
    val name: String,
    val issuer: String,
    val scopes: String,
    val mobileClientId: String?,
)
