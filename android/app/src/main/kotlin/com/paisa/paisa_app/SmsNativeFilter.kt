package com.paisa.paisa_app

/**
 * Coarse on-device pre-filter for bank / UPI SMS.
 *
 * This is ONLY a cheap thinner that keeps obviously non-financial and OTP-only
 * messages off the platform channel. It intentionally does NOT try to reject
 * promo / scam SMS or make the final "is this a transaction?" decision — the
 * authoritative gate (promo, scam-obfuscation, personal-sender, transaction
 * signal) lives in Dart (`SmsScanPipeline` / `SmsParser`) and re-runs on every
 * candidate in the background isolate. Over-returning candidates here is safe;
 * Dart re-gates. Keeping the promo/scam logic in exactly one place (Dart) avoids
 * the Kotlin/Dart drift that previously let filters disagree. See ISSUE-2.
 */
object SmsNativeFilter {
    private val senderHints = listOf(
        "HDFC", "HDFCBK", "SBI", "SBIN", "SBICRD", "SBICGV", "ICICI", "ICICIO",
        "ICICIT", "AXIS", "KOTAK", "KOTAKB", "PAYTM", "PHONEPE",
        "GPAY", "GOOGLEPAY", "GOOGLE", "BHIM", "YESBNK", "YESBANK", "INDUS",
        "PNB", "CANARA", "BARODA", "FEDERAL", "IDFC", "IDFCFB", "UPI", "NEFT",
        "IMPS", "LENDEN", "HSBCIN", "HSBC"
    )

    private val bodyBankHints = listOf(
        "hdfc", "sbi", "icici", "axis bank", "axis", "kotak", "paytm",
        "phonepe", "google pay", "gpay", "yes bank", "indusind", "pnb",
        "canara", "bank of baroda", "idfc", "hsbc"
    )

    private val bodyTxnHints = listOf(
        "debited", "credited", "spent", "paid", "received", "withdrawn",
        "deposited", "upi", "neft", "imps", "rtgs", "a/c", "acct", "account",
        "bal ", "balance", "rs.", "rs ", "inr ", "₹", "credit card", "emi",
        "loan a/c", "card ending"
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

    /**
     * Coarse pass: returns true when an SMS is worth sending to Dart for the
     * real (authoritative) gate + regex parse. Keeps obviously non-financial
     * and OTP-only messages off the channel; promo/scam rejection and the final
     * transaction decision are deferred to Dart. See ISSUE-2.
     */
    fun passesPreFilter(sender: String, body: String): Boolean {
        val trimmed = body.trim()
        if (trimmed.length >= 20 && isFinancialSender(sender) && looksLikeOtp(trimmed)) {
            return false
        }
        if (!passesFinancialGate(sender, trimmed)) return false
        if (looksLikeOtp(trimmed)) return false
        if (!hasTransactionSignal(trimmed)) return false
        return true
    }
}
