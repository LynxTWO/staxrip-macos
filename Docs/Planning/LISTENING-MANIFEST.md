# Slice 002 listening material

Acquisition permission established 2026-09-28, before downloading media. Hashes and exact excerpts are populated after acquisition and before listening use.

## Source permitted for local evaluation

Sintel (2010), © Blender Foundation, https://www.sintel.org/ . The official [sharing page](https://durian.blender.org/sharing/) licenses the film and project material under [Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/). It excludes logos/trademarks and unrelated third-party material. The page was checked directly before acquisition; a local copy is retained outside Git.

Acquisition: https://download.blender.org/durian/movies/Sintel.2010.720p.mkv.zip from the official download directory. Purpose: local excerpts and modified audio for owner comparison of mastering modes. Retain original file, credits and attribution; label derived audio as modified. No media will be committed to Git or uploaded to hosted CI. No endorsement by the filmmakers is implied.

Coverage sought: six 30-to-60-second passages spanning quiet dialogue, dialogue/action transitions, music under speech, transients, ambience and differing speaker levels. Determine actual coverage after inspection; do not claim it from the film title. The expected spoken language is English. Second-language coverage is not yet established; no multilingual quality claim is permitted.

Acquisition/hash state: complete; see below. Excerpt and level-match receipts: complete for the explicitly wider research settings below. Owner listening ratings and coverage confirmation: pending. These remain unmet acceptance evidence, not passed gates.

## Acquired source identity

- Archive SHA-256: `d252f898641b20f51c64206f31063e659c28b152a9d988936736d1b56e6e4db3`.
- Film SHA-256: `f12c070e295b38cfc94ebd61ac3357c3bac82d1015985f1e8da93a4c6496c46d`.
- Prepared stereo FLAC SHA-256: `7512d492a4d479a6c5ffe5429dce35077aab653bfdc8362a2529a6a4ce323306`.

The acquired audio is English AC-3, 48 kHz, 5.1(side). Fixture preparation (not an app feature) explicitly disables AC-3 DRC with `-drc_scale 0`, omits LFE, and forms left/right from `0.4142135624*front + 0.2928932188*centre + 0.2928932188*same-side surround`. It encodes 24-bit 48 kHz stereo FLAC using local FFmpeg 9.0.2. The original file/credits remain local. This derived stereo mix is modified audio, not an official studio stereo master, and cannot establish surround fidelity. Other languages in the file are subtitles only.

## Full-source feasibility decision

The first default Smart request (-18 LUFS, maximum 11 LU) refused after three attempts because programme LRA remained above 12 LU. No candidate was published. Independent source measurement: -23.8 LUFS, 25.1 LU LRA, LRA low -43.9 LUFS/high -18.8 LUFS, true peak -3.2 dBTP. With a +12 dB boost cap, the quiet range endpoint cannot simply be lifted to -18 LUFS. This is a planner/request failure to expose, not proof that no algorithm could comply. It does not justify increasing permitted boost or weakening tolerance.

For the next explicitly declared feasibility trial, use Smart -23 LUFS/11 LU and Night -30 LUFS/3 LU. These remain inside the approved target range and retain the +12 dB bound. They are trial settings for this source, not replacement app defaults or passing results. All listening comparisons must subsequently level-match the excerpts; this must not disguise the failed default request.

The lower-target trial also failed: Smart ended at 16.67 LU LRA (limit 12); Night ended at 11.18 LU (limit 4). No candidates were published. MASTERING-M1.md registers a short-term-control revision for evaluation; previous successful numerical and resource receipts apply to the earlier revision until rechecked.

The bounded revision 3 feedback planner improved some generated cases but also failed the full film: final Smart -25.94 LUFS/13.46 LU and Night -34.26/5.93, against the requests above. Variants 4 through 6 did not pass predicted preflight and were not rendered as listening candidates. The retained revision 3 has full-output numerical evidence, including failures. No concealed-label listening pack is ready; owner listening acceptance is still pending. A new planning-objective review is required before more smoothing variants.

## Explicit alternative listening requests

After the objective investigation, two separately declared settings on the retained planner produced verified full-film candidates on their first render: Smart requested -23 LUFS / 20 LU maximum and measured -23.00 / 19.42 with -1.51 dBTP; Night requested -30 / 11 and measured -30.01 / 10.60 with -1.39 dBTP. These do not supersede failed requests or change defaults. Listening these candidates cannot establish 3 LU performance.

The existing FFmpeg Night baseline at -30 / 11 refused its range check. Preserve that failure. Before a separate baseline preparation run, explicitly request -30 / 20. Its settings will be disclosed with the comparison key; the listening screen is not a same-range superiority comparison. The original and a peak-safe constant-gain control are also required. All five versions will be cut from full-film processing at identical frame positions, with attenuation-only per-excerpt level matching and freshly measured final files. Planned intervals are 100, 200, 245, 320, 440 and 585 seconds, each 45 seconds long. The accompanying English subtitles support dialogue placement; coverage of music, transients and ambience must still be confirmed by the owner while listening.

## Prepared local review

The separately requested legacy -30 / 20 baseline passed: -29.97 LUFS, 20.84 LU LRA and -7.54 dBTP. Six groups of five 45-second 24-bit stereo FLACs are now prepared at the intervals above. Each contains original, peak-safe constant gain, existing FFmpeg Night, retained Swift Smart and retained Swift Night. Labels A through E are independently shuffled per group with seed 9282026. This is a concealed-label owner screen, not a double-blind study. The constant and original controls should be nearly identical after matching.

The first preparation used loudnorm input measurements and passed its own within-group check, but a separate Swift check found a 0.1851 LU discrepancy from the declared matching target. That pack is superseded and is not the owner handoff. Do not conceal this failed cross-check or loosen its 0.15 LU threshold.

The rebuilt pack uses the same unpadded ebur128 measurement path as app verification, with milliloudness precision from filter metadata. All 30 final files have 2,160,000 frames at 48 kHz, two channels and 24-bit lossless encoding. Maximum within-group integrated difference is 0.029 LU in ebur128 and 0.0288 LU in the independent Swift meter, versus the 0.2 LU allowance. All Swift readings also agree with the declared matching targets within 0.15 LU. Matching uses attenuation only; the largest ebur128 matched true peak is -5.4 dBTP. File hashes were rechecked. The final local manifest's SHA-256 is `52b5c998bbc1ab102f744a4d5c6db0055a09958aa6e9df69f21b09ab82efbe94`. Neither media nor the concealed mapping is committed to Git.

An additional correlation check over the central five seconds of each clip found zero-sample lag relative to that group's original version for all 30 files. This is a bounded alignment check, not proof of full waveform identity or sound quality.

The local index provides a paused player, five options, shared position, an excerpt selector, attribution and a blank 30-row ratings sheet. A range-capable localhost server is required for reliable browser seeking. The original simple server failed that check and was replaced. Keyboard playback, a shared 7.3-second position across an option switch, paused switching and reset to zero on a new excerpt were observed in the local browser. This establishes playback behavior, not audio quality or spoken VoiceOver acceptance.

Reproduce with `scripts/prepare-listening-pack.py --help`; it requires the manifest source, verified Smart/Night files and their receipts, the verified legacy file and its fresh analysis, and a new output directory. Then set `STAXRIP_LISTENING_PACK` to that directory and run `swift test -c release --filter independentMeterVerifiesConcealedListeningPack`. This independently checks all files and writes a manifest-bound receipt only on success. Serve that directory using `scripts/serve-listening-pack.py DIRECTORY`; it refuses a missing or mismatched independent receipt. Both scripts stay local. The server binds only to 127.0.0.1; normal, suffix, invalid and HEAD byte-range responses were checked against file bytes. Output remains marked incomplete until every preparation frame/level check passes, and the independent receipt is separately required before serving.

Owner action: compare options at fixed playback volume within each excerpt and record intelligibility, pumping, transient damage, stereo image, fatigue, preferences/ties and timestamps. Confirm the six requested coverage categories. Keep the review key closed until rating. This wider-range pack cannot establish the failed 3 LU request or multilingual/surround quality. S2-008 and D-015 remain open pending that feedback and the unresolved algorithm work.
