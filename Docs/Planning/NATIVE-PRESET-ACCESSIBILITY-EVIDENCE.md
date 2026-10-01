# Native preset accessibility evidence

Date: 2026-09-30. Slice 023, D-036 / R-026. Status: existing regression passed; app build passed in 14.82 seconds; native/hosted pending.

Quick Export derives a short native-preset label through the shared spokenCodecs helper, so H.264 becomes H two six four. A Selected or Not selected value follows the actual NativePreset selection. Visible preset names remain input aliases for voice control. Optional hints retain the Apple-preset explanation, expand AVC/HEVC, and explain that workspace encoding settings do not apply. Visible text, native preset identifiers and encoder behavior are unchanged.

No new tests mirror the text literals. The existing release regression passed 189 tests in 37 suites in 37.420 seconds. Native accessibility-tree inspection will verify exported names, hints and selection transitions in the rebuilt app. That is not a spoken VoiceOver or voice-control recognition test; owner listening and broader platform/keyboard qualification remain separate. No system accessibility preference is changed. Audio mastering/listening remains parked.
