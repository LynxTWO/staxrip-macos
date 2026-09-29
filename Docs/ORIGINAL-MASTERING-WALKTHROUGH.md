# Original mastering walkthrough

Experimental development build. Numerical and native verification are in Planning/MASTERING-EVIDENCE.md; real-film numerical feasibility and listening acceptance remain open. This is mono/stereo processing. Automatic speech detection and surround mastering are not included.

1. Open Audio Lab and a supported source. Choose the source track and an explicit layout only if its metadata is missing and you know the layout.
2. In Optional speech intervals, enter representative passages if you want a speech anchor. Select Original mastering's Selected speech reference and confirm the intervals. Music/effects inside them are measured too. Whole programme requires no speech selection.
3. Choose Smart or Night, target LUFS and maximum LRA, then Build fresh plan. Check the programme/speech readings, base gain, envelope bounds and temporary disk estimate. Changing source, intervals, layout or targets invalidates the candidate; interval/source changes also clear speech confirmation.
4. Render verified candidate and choose a new FLAC or WAV filename. This stages audio; it does not publish that filename yet. Wait for independent verification or use Cancel original mastering or Escape. Refusals preserve the source and prior files. A refusal can reflect a planner limitation as well as conflicting constraints. You may explicitly try other settings; no target is changed automatically. The licensed full-film trial currently fails the required range/reference checks, so this build is not ready for production Midnight processing.
5. Enter an excerpt start and a duration between 5 and 60 seconds, wholly inside the source. Build aligned excerpt. Playback starts paused. Play, switch Original/Processed, seek, and try Level-match. Switching/seeking/matching pauses playback. Matching attenuates playback only; the saved audio stays unchanged.
6. Save verified audio. Then optionally Save processing report. They are separate saves; report failure does not undo successfully saved audio. Use a new report filename to retry.
7. Discard candidate clears owned staging and preview files. Normal app quit also cleans staging. Published output remains. A forced crash can leave a hidden `.staxrip-master-*` folder beside the destination; never delete arbitrary folders in recovery.

For spoken review, verify reference labels, confirmation, target units, each before/after value, refusal explanation, cancellation, Original/Processed, shared position and separate save result. The small result fields expose individual labels/values. Note any pronunciation or focus problem.

Listening review requires the separate licensed comparison pack and concealed labels. Rate speech intelligibility, pumping/breathing, transients, stereo image and fatigue individually. A short owner screen does not establish universal comfort or best-in-class quality.
