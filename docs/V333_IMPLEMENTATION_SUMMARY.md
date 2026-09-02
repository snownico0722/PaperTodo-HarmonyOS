# 3.3.3 implementation summary

The taskbar fix moves the HOME skill to `ManagerAbility`, so the system taskbar/launcher mission owns the Settings window directly. `EntryAbility` remains an internal hidden runtime host used for tray/resident startup and paper/capsule restoration.

The capsule fix separates native-window styling calls, reapplies transparent background/container colors after ArkUI content loads, measures the master row rather than fixing it at 200vp, and removes ordinary capsule rows from layout while the queue is retracted. The native host therefore shrinks to the single master row instead of retaining an invisible full-height interaction rectangle.

The cross-paper drag association handle is gated off in the paper top bar. Existing association storage/protocol code remains unchanged.
