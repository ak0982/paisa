package com.paisa.paisa_app

/**
 * Fast on-device pre-filter for bank / UPI SMS (stages 1–4).
 * Heavy regex parsing stays in Dart on a background isolate.
 */
object SmsNativeFilter {
    private val senderHints = listOf(
        "HDFC", "HDFCBK", "SBI", "SBIN", "SBICRD", "SBICGV", "ICICI", "ICICIO",
        "ICICIT", "AXIS", "KOTAK", "KOTAKB", "PAYTM", "PHONEPE",
        "GPAY", "GOOGLEPAY", "GOOGLE", "BHIM", "YESBNK", "YESBANK", "INDUS",
        "PNB", "CANARA", "BARODA", "FEDERAL", "IDFC", "IDFCFB", "UPI", "NEFT",
        "IMPS", "LENDEN"
    )

    private val bodyBankHints = listOf(
        "hdfc", "sbi", "icici", "axis bank", "axis", "kotak", "paytm",
        "phonepe", "google pay", "gpay", "yes bank", "indusind", "pnb",
        "canara", "bank of baroda", "idfc"
    )

    private val bodyTxnHints = listOf(
        "debited", "credited", "spent", "paid", "received", "withdrawn",
        "deposited", "upi", "neft", "imps", "rtgs", "a/c", "acct", "account",
        "bal ", "balance", "rs.", "rs ", "inr ", "₹", "credit card", "emi",
        "loan a/c", "card ending"
    )

    private val promoHints = listOf(
        "pre-approved", "pre approved", "loan offer", "personal loan",
        "instant loan", "apply now", "click here", "limited period",
        "credit card offer", "exclusive offer", "smartemi", "easyemi",
        "yono offer", "grab deals", "refer and earn", "scratch card",
        "cashback offer", "kotak 811 offer"
    )

    private val completedTxnHints = listOf(
        "debited", "sent rs", "paid to", "paid at", "spent at", "spent on",
        "withdrawn", "deposited", "neft dr", "neft cr", "imps dr",
        "imps cr", "rtgs dr", "rtgs cr", "credited to", "payment of",
        "payment received", "has been received"
    )

    fun isFinancialSender(sender: String): Boolean {
        if (sender.isEmpty()) return false
        val upper = sender.uppercase()
        return senderHints.any { upper.contains(it) }
    }

    fun hasFinancialBodyHint(body: String): Boolean {
        if (body.length < 20) return false
        val lower = body.lowercase()
        return bodyBankHints.any { lower.contains(it) } ||
            bodyTxnHints.any { lower.contains(it) }
    }

    fun passesFinancialGate(sender: String, body: String): Boolean {
        val trimmed = body.trim()
        if (trimmed.length < 20) return false
        if (hasFinancialBodyHint(trimmed)) return true
        return isFinancialSender(sender) && hasTransactionSignal(trimmed)
    }

    fun looksLikeOtp(body: String): Boolean {
        val lower = body.lowercase()
        if (hasTransactionSignal(body)) return false
        return lower.contains("otp") ||
            lower.contains("one time password") ||
            lower.contains("verification code") ||
            lower.contains("do not share")
    }

    fun isPromo(sender: String, body: String): Boolean {
        val lower = body.lowercase()
        if (completedTxnHints.any { lower.contains(it) }) return false
        if (promoHints.any { lower.contains(it) }) return true
        return BankPromoNative.matches(sender, body)
    }

    fun hasTransactionSignal(body: String): Boolean {
        val lower = body.lowercase()
        return bodyTxnHints.any { hint ->
            when (hint) {
                "bal " -> lower.contains("bal ")
                "rs." -> lower.contains("rs.")
                "rs " -> lower.contains("rs ")
                "inr " -> lower.contains("inr ")
                "₹" -> body.contains("₹")
                else -> lower.contains(hint)
            }
        }
    }

    /** Stages 1–4: returns true when SMS should be sent to Dart for regex parse. */
    fun passesPreFilter(sender: String, body: String): Boolean {
        val trimmed = body.trim()
        if (trimmed.length >= 20 && isFinancialSender(sender) && looksLikeOtp(trimmed)) {
            return false
        }
        if (!passesFinancialGate(sender, trimmed)) return false
        if (looksLikeOtp(trimmed)) return false
        if (isPromo(sender, trimmed)) return false
        if (!hasTransactionSignal(trimmed)) return false
        return true
    }
}

/** Bank-specific promo phrases mirrored from Dart [BankPromoFilters]. */
private object BankPromoNative {
    private val senderBank = mapOf(
        "hdfc" to "HDFC", "sbi" to "SBI", "icici" to "ICICI", "axis" to "Axis",
        "kotak" to "Kotak", "paytm" to "Paytm", "phonepe" to "PhonePe"
    )

    private val bankPromos = mapOf(
        "HDFC" to listOf("smartemi", "easyemi", "10x rewards", "millennia offer", "payzapp offer"),
        "SBI" to listOf("yono offer", "simplyclick", "simplysave", "prime card offer"),
        "ICICI" to listOf("imobile offer", "amazon pay icici", "coral offer", "ascend offer"),
        "Axis" to listOf("grab deals", "axis neo offer", "flipkart axis offer"),
        "Kotak" to listOf("kotak 811 offer", "dream different offer"),
        "Paytm" to listOf("cashback offer", "refer and earn", "scratch card", "paytm offer"),
        "PhonePe" to listOf("cashback offer", "refer and earn", "scratch card", "phonepe offer")
    )

    fun matches(sender: String, body: String): Boolean {
        val bank = detectBank(sender, body) ?: return false
        val promos = bankPromos[bank] ?: return false
        val lower = body.lowercase()
        return promos.any { lower.contains(it) }
    }

    private fun detectBank(sender: String, body: String): String? {
        val s = sender.lowercase()
        for ((key, bank) in senderBank) {
            if (s.contains(key)) return bank
        }
        val b = body.lowercase()
        for ((key, bank) in senderBank) {
            if (b.contains(key)) return bank
        }
        return null
    }
}
