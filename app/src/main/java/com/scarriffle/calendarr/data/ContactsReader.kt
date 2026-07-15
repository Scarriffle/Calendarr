package com.scarriffle.calendarr.data

import android.content.Context
import android.provider.ContactsContract

/** One birthday read from the address book. */
data class ContactBirthday(
    val contactId: String,
    val name: String,
    val month: Int,
    val day: Int,
    val year: Int?,
)

/** Reads birthdays from the system Contacts (requires READ_CONTACTS). */
object ContactsReader {

    fun readBirthdays(context: Context): List<ContactBirthday> {
        val out = mutableListOf<ContactBirthday>()
        val projection = arrayOf(
            ContactsContract.Data.CONTACT_ID,
            ContactsContract.CommonDataKinds.Event.START_DATE,
            ContactsContract.Data.DISPLAY_NAME,
        )
        val selection = "${ContactsContract.Data.MIMETYPE} = ? AND ${ContactsContract.CommonDataKinds.Event.TYPE} = ?"
        val args = arrayOf(
            ContactsContract.CommonDataKinds.Event.CONTENT_ITEM_TYPE,
            ContactsContract.CommonDataKinds.Event.TYPE_BIRTHDAY.toString(),
        )
        context.contentResolver.query(ContactsContract.Data.CONTENT_URI, projection, selection, args, null)
            ?.use { c ->
                val idIdx = c.getColumnIndexOrThrow(ContactsContract.Data.CONTACT_ID)
                val dateIdx = c.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Event.START_DATE)
                val nameIdx = c.getColumnIndexOrThrow(ContactsContract.Data.DISPLAY_NAME)
                while (c.moveToNext()) {
                    val raw = c.getString(dateIdx) ?: continue
                    val name = c.getString(nameIdx)?.takeIf { it.isNotBlank() } ?: continue
                    val id = c.getString(idIdx) ?: continue
                    val ymd = parseDate(raw) ?: continue
                    out.add(ContactBirthday(id, name, ymd.second, ymd.third, ymd.first))
                }
            }
        // A contact could carry more than one birthday row — keep the first.
        return out.distinctBy { it.contactId }
    }

    /** Returns (year?, month, day). Handles "yyyy-MM-dd", "--MM-dd" (no year),
     *  and "yyyyMMdd". */
    private fun parseDate(raw: String): Triple<Int?, Int, Int>? = try {
        val s = raw.trim()
        when {
            s.startsWith("--") -> {
                val p = s.removePrefix("--").split("-")
                Triple(null, p[0].toInt(), p[1].toInt())
            }
            s.contains("-") -> {
                val p = s.split("-")
                if (p.size == 3) Triple(p[0].toIntOrNull()?.takeIf { it > 0 }, p[1].toInt(), p[2].toInt()) else null
            }
            s.length == 8 -> Triple(s.substring(0, 4).toInt().takeIf { it > 0 }, s.substring(4, 6).toInt(), s.substring(6, 8).toInt())
            else -> null
        }
    } catch (e: Exception) {
        null
    }
}
