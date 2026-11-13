package com.wimg.app.services

import android.content.Context
import com.wimg.app.bridge.LibWimg
import java.text.NumberFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.abs
import kotlin.random.Random

object DemoDataService {
    private const val DEMO_LOADED_KEY = "wimg_demo_loaded"

    private data class FixedTx(val desc: String, val amount: Int?)
    private data class FrequentTx(val desc: String, val min: Int, val max: Int, val freqMin: Int, val freqMax: Int)
    private data class OccasionalTx(val desc: String, val min: Int, val max: Int)

    private val fixedMonthly = listOf(
        FixedTx("GEHALT {MONTH} 2026 MUSTER GMBH", 325_000),
        FixedTx("MIETE {MONTH} 2026 HAUSVERWALTUNG MUSTERSTADT", -95_000),
        FixedTx("GRUENSTROM AG STROM GAS", null),
        FixedTx("FLIMMERKISTE STREAMING", -1_799),
        FixedTx("KLANGWELLE STREAMING", -999),
        FixedTx("MUSTER VERSICHERUNG AG", -8_950),
        FixedTx("RUNDFUNKBEITRAG", -1_836),
        FixedTx("FUNKLINE MOBILFUNK", -3_999),
    )

    private val frequent = listOf(
        FrequentTx("SUPERMARKT AM PARK {id}//MUSTERSTADT/DE", -8_500, -1_500, 3, 4),
        FrequentTx("KORNFELD SUPERMARKT", -4_500, -1_200, 2, 3),
        FrequentTx("FRISCHE ECKE SUPERMARKT {id}", -5_500, -800, 2, 3),
        FrequentTx("DROGERIE SONNENSCHEIN", -2_500, -500, 1, 2),
        FrequentTx("MUSTERSTADT VERKEHRSBETRIEBE", -4_500, -1_500, 1, 2),
    )

    private val occasional = listOf(
        OccasionalTx("PIZZERIA BELLA LUNA", -3_500, -1_200),
        OccasionalTx("KAUFHAUS ZENTRUM", -12_000, -1_500),
        OccasionalTx("DROGERIE AM ECK", -2_000, -500),
        OccasionalTx("APOTHEKE AM MARKT", -3_000, -500),
    )

    private val monthNames = arrayOf(
        "", "JANUAR", "FEBRUAR", "MAERZ", "APRIL", "MAI", "JUNI",
        "JULI", "AUGUST", "SEPTEMBER", "OKTOBER", "NOVEMBER", "DEZEMBER",
    )

    fun loadDemoData(context: Context) {
        val csv = generateDemoCSV()
        val data = csv.toByteArray(Charsets.ISO_8859_1)
        val result = LibWimg.importCsv(data)
        if (result != null && result.imported > 0) {
            LibWimg.autoCategorize()
            context.getSharedPreferences("wimg", 0).edit().putBoolean(DEMO_LOADED_KEY, true).apply()
        }
    }

    private fun generateDemoCSV(): String {
        val cal = Calendar.getInstance()
        data class Row(val date: String, val desc: String, val amount: String, val sortKey: Int)
        val rows = mutableListOf<Row>()

        for (offset in 0 until 3) {
            cal.time = java.util.Date()
            cal.add(Calendar.MONTH, -offset)
            val year = cal.get(Calendar.YEAR)
            val month = cal.get(Calendar.MONTH) + 1
            val maxDay = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
            val monthName = monthNames[month]

            // Fixed monthly
            for (tx in fixedMonthly) {
                val day = Random.nextInt(1, minOf(6, maxDay + 1))
                val desc = tx.desc.replace("{MONTH}", monthName)
                val cents = tx.amount ?: Random.nextInt(-11_500, -9_499)
                rows.add(Row(formatDate(year, month, day), desc, formatAmount(cents), year * 10000 + month * 100 + day))
            }

            // Frequent
            for (tx in frequent) {
                val count = Random.nextInt(tx.freqMin, tx.freqMax + 1)
                repeat(count) {
                    val day = Random.nextInt(1, maxDay + 1)
                    val id = Random.nextInt(10000, 100000).toString()
                    val desc = tx.desc.replace("{id}", id)
                    val cents = Random.nextInt(tx.min, tx.max + 1)
                    rows.add(Row(formatDate(year, month, day), desc, formatAmount(cents), year * 10000 + month * 100 + day))
                }
            }

            // Occasional
            for (tx in occasional) {
                val count = Random.nextInt(0, 3)
                repeat(count) {
                    val day = Random.nextInt(5, maxDay + 1)
                    val cents = Random.nextInt(tx.min, tx.max + 1)
                    rows.add(Row(formatDate(year, month, day), tx.desc, formatAmount(cents), year * 10000 + month * 100 + day))
                }
            }
        }

        rows.sortByDescending { it.sortKey }

        val header = "\"Buchungstag\";\"Wertstellung (Valuta)\";\"Vorgang\";\"Buchungstext\";\"Umsatz in EUR\""
        val lines = rows.joinToString("\n") { r ->
            "\"${r.date}\";\"${r.date}\";\"Lastschrift\";\"${r.desc}\";\"${r.amount}\""
        }
        return "$header\n$lines\n"
    }

    private fun formatDate(year: Int, month: Int, day: Int): String {
        return String.format("%02d.%02d.%04d", day, month, year)
    }

    private fun formatAmount(cents: Int): String {
        val sign = if (cents < 0) "-" else ""
        val absCents = abs(cents)
        val eur = absCents / 100
        val ct = absCents % 100
        val nf = NumberFormat.getIntegerInstance(Locale.GERMANY)
        return "$sign${nf.format(eur)},${String.format("%02d", ct)}"
    }
}
