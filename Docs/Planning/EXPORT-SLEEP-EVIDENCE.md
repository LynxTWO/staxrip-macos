# Export idle-sleep lifetime evidence
Date: 2026-10-01. Status: M1 passed; product acceptance pending.

## Need, references and boundary

R-051 / D-079 covers temporary local energy policy for existing video-export lifetimes. The two relevant owners are BatchController.start and NativeExportService.export. No automatic-sleep activity calls were found in those two examined files; this says nothing about external tools, frameworks or other processes. [Apple activity options](https://developer.apple.com/documentation/Foundation/ProcessInfo/ActivityOptions) distinguishes idle system sleep from idle display sleep. [Apple's activity guidance](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheAppLevel.html) documents matched begin/end calls and pmset inspection. Use only idleSystemSleepDisabled; no QoS, display, lock, persistent preference or audio changes.

## M1 actual system request

A local Swift/Foundation experiment on macOS 27.0.1 creates two uniquely named activity tokens. pmset -g assertions identifies both as PreventUserIdleSystemSleep owned by the experiment PID. Ending the first removes only its named assertion; the second remains. Ending the second removes both. No matching display-sleep assertion appears. The successful experiment completed in under one second within the five-minute bound. A preceding Swift autoclosure syntax error executed no experiment and is retained separately; correcting it changed no runtime assertion.

Claim: observed_behavior, verified within these two named process-local tokens. Consequence: local_only. Evidence: private export-sleep/feasibility.swift and feasibility.log. This is not forced-sleep, power-exhaustion, screen-lock, lid-close or platform-matrix qualification. M2 may proceed; actual application lifetimes and native UI remain pending.
