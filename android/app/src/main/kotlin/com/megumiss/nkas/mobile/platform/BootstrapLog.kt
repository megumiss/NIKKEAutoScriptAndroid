package com.megumiss.nkas.mobile.platform

internal object BootstrapLog {
    private val stateSection = Regex("""(?m)^---STATE---\r?\n([^\r\n]*)\r?\n---LOG---(?:\r?\n|$)""")

    // The log tail contains older state= entries; only the state file is current.
    fun state(output: String): String? = stateSection.find(output)
        ?.groupValues?.get(1)?.trim()?.takeIf { it.isNotEmpty() }
}
