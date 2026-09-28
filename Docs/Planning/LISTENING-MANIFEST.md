# Slice 002 listening material

Acquisition permission established 2026-09-28, before downloading media. Hashes and exact excerpts are populated after acquisition and before listening use.

## Source permitted for local evaluation

Sintel (2010), © Blender Foundation, https://www.sintel.org/ . The official [sharing page](https://durian.blender.org/sharing/) licenses the film and project material under [Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/). It excludes logos/trademarks and unrelated third-party material. The page was checked directly before acquisition; a local copy is retained outside Git.

Acquisition: https://download.blender.org/durian/movies/Sintel.2010.720p.mkv.zip from the official download directory. Purpose: local excerpts and modified audio for owner comparison of mastering modes. Retain original file, credits and attribution; label derived audio as modified. No media will be committed to Git or uploaded to hosted CI. No endorsement by the filmmakers is implied.

Coverage sought: six 30-to-60-second passages spanning quiet dialogue, dialogue/action transitions, music under speech, transients, ambience and differing speaker levels. Determine actual coverage after inspection; do not claim it from the film title. The expected spoken language is English. Second-language coverage is not yet established; no multilingual quality claim is permitted.

Acquisition/hash state: complete; see below. Excerpt and level-match receipts: pending. Owner listening ratings: pending. These remain unmet acceptance evidence, not passed gates.

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
