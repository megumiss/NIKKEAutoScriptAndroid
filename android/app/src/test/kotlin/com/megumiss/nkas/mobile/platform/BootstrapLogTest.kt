package com.megumiss.nkas.mobile.platform

import org.junit.Assert.*
import org.junit.Test

class BootstrapLogTest {
    private fun snapshot(state: String, history: String) =
        "---STATE---\n$state\n---LOG---\n$history\n---SERVICE---\nservice output\n"

    @Test fun completionIsNotHiddenByEarlierRunningStages() {
        val output = snapshot("ready", """
            [nkas] state=installing-termux-tools
            [nkas] state=cloning-nkas
            [nkas] state=creating-config
            [nkas] state=installing-container
            [nkas] state=starting-nkas
            [nkas] state=ready
        """.trimIndent())

        assertEquals("ready", BootstrapLog.state(output))
        assertEquals("ready", BootstrapLog.state(output.replace("\n", "\r\n")))
    }

    @Test fun failureIsNotHiddenByEarlierRunningStages() {
        assertEquals("failed", BootstrapLog.state(snapshot("failed", """
            [nkas] state=installing-container
            [nkas] state=starting-nkas
            [nkas] ERROR: Web UI health check timed out
            [nkas] state=failed
        """.trimIndent())))
    }

    @Test fun historyCannotCompleteOrFailTheCurrentStage() {
        for (state in listOf(
            "installing-termux-tools", "cloning-nkas", "creating-config",
            "installing-container", "starting-nkas",
        )) {
            assertEquals(state, BootstrapLog.state(snapshot(
                state, "[nkas] state=ready\n[nkas] state=failed",
            )))
        }
    }

    @Test fun terminalStateDoesNotRequireAMatchingHistoryEntry() {
        for (state in listOf("ready", "failed")) {
            assertEquals(state, BootstrapLog.state(snapshot(state, "[nkas] state=starting-nkas")))
        }
    }

    @Test fun missingOrIncompleteStateDoesNotUseLogHistory() {
        for (output in listOf(
            "",
            "[nkas] state=ready\n---SERVICE---\n[nkas] state=failed\n",
            "---STATE---\n---LOG---\n[nkas] state=ready\n",
            snapshot("", "[nkas] state=ready"),
            "---STATE---\nready",
            "---STATE---\nready\nfailed\n---LOG---\n",
        )) {
            assertNull(BootstrapLog.state(output))
        }
    }
}
