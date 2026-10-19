package io.github.dey410.gardendlessloader.game

/** Makes the final rename and host shutdown mutually exclusive. */
internal class FileCommitGate {
    @Volatile var active = true
        private set

    @Synchronized fun stop(): Boolean {
        if (!active) return false
        active = false
        return true
    }

    @Synchronized fun commit(operation: () -> Unit) {
        check(active) { "Game host was destroyed" }
        operation()
    }
}
